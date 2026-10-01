# frozen_string_literal: true

require "json"
require "fileutils"

# The gate's mutation report: reads the JSON Mutineer wrote, re-runs every
# subject a mutant came back without a verdict for, prints what it found, and
# decides whether the step passes. Every collaborator that would otherwise
# shell out (the first run, a re-run) is injected, so a unit test never
# starts Mutineer.
module MutationVerdicts
  THRESHOLD = 75

  # One id a re-run gave a verdict (or not) to, with the subject and
  # location its mutant came from, for printing and deciding alike.
  Resolved = Struct.new(:id, :subject, :file, :line, :status)

  # One Mutineer JSON report, read fresh every time so a file left behind by
  # an earlier, unrelated run is never mistaken for this one's.
  class Report
    def self.read(path)
      return nil unless File.exist?(path)

      new(JSON.parse(File.read(path)))
    end

    def initialize(data)
      @data = data
    end

    def survivors = @data.fetch("survivors")

    def no_verdict = @data.fetch("no_verdict")

    def summary = @data.fetch("summary")
  end

  # Re-runs every subject whose mutants came back without a verdict, one
  # subject at a time, and reports what each re-run found and how long it
  # took. A mutant with no subject failed before Mutineer could fork a
  # worker for it, so there is nothing to isolate and re-run.
  class Rerunner
    def initialize(rerun:, out:)
      @rerun = rerun
      @out = out
    end

    def resolve(no_verdict)
      with_subject, without_subject = no_verdict.partition { |mutant| mutant["subject"] }
      resolved = with_subject.group_by { |mutant| mutant.fetch("subject") }.flat_map { |subject, mutants| rerun_one(subject, mutants) }
      [resolved, without_subject]
    end

    private

    def rerun_one(subject, mutants)
      ids = mutants.map { |mutant| mutant.fetch("id") }
      statuses, seconds = @rerun.call(subject, ids)
      @out.puts format("Re-ran %s alone: %.1fs", subject, seconds)
      mutants.map { |mutant| Resolved.new(mutant.fetch("id"), subject, mutant.fetch("file"), mutant.fetch("line"), statuses.fetch(mutant.fetch("id"))) }
    end
  end

  # Decides whether the step passes: no mutant without a subject to re-run,
  # no id still without a verdict after the re-run, and a score at or over
  # the threshold. A report with nothing attempted passes with nothing to
  # mutate.
  class Decision
    Failure = Class.new(StandardError)

    def self.score_of(report, resolved)
      killed = report.summary.fetch("killed") + resolved.count { |entry| entry.status == "killed" }
      survived = report.summary.fetch("survived") + resolved.count { |entry| entry.status == "survived" }
      total = killed + survived
      return 100.0 if total.zero?

      (killed * 100.0 / total).round(1)
    end

    def initialize(threshold: THRESHOLD)
      @threshold = threshold
    end

    def decide!(resolved, pre_fork_failures, score)
      raise Failure, pre_fork_message(pre_fork_failures) unless pre_fork_failures.empty?

      unresolved = resolved.select { |entry| entry.status == "no_verdict" }
      raise Failure, "still without a verdict: #{unresolved.map(&:id).join(", ")}" unless unresolved.empty?
      raise Failure, format("mutation score %.1f%% is under the %d%% threshold", score, @threshold) if score < @threshold
    end

    private

    def pre_fork_message(pre_fork_failures)
      "failed before a worker forked, with no subject to re-run: #{pre_fork_failures.map { |mutant| "#{mutant.fetch("file")}:#{mutant.fetch("line")}" }.join(", ")}"
    end
  end

  # Prints the gate's own mutation report: every survivor with its diff, and
  # every mutant still without a verdict, named by subject and location.
  class Printer
    def initialize(out)
      @out = out
    end

    def print(report, resolved, pre_fork_failures, score)
      @out.puts format("Mutation score: %.1f%%", score)
      report.survivors.each { |survivor| print_survivor(survivor) }
      print_unresolved(resolved, pre_fork_failures)
    end

    private

    def print_survivor(survivor)
      @out.puts "Survived: #{survivor.fetch("subject")} #{survivor.fetch("file")}:#{survivor.fetch("line")}"
      @out.puts survivor.fetch("diff")
    end

    def print_unresolved(resolved, pre_fork_failures)
      resolved.select { |entry| entry.status == "no_verdict" }.each { |entry| @out.puts "No verdict: #{entry.subject} #{entry.file}:#{entry.line}" }
      pre_fork_failures.each { |mutant| @out.puts "No verdict: (no subject) #{mutant.fetch("file")}:#{mutant.fetch("line")}" }
    end
  end

  # One gate run against an already-written report: resolve what Mutineer
  # left without a verdict, print the report, then decide.
  class Gate
    def initialize(path, rerun:, out: $stdout, threshold: THRESHOLD)
      @path = path
      @rerun = rerun
      @out = out
      @threshold = threshold
    end

    def call
      report = Report.read(@path)
      raise Decision::Failure, "missing mutation report: #{@path}" unless report

      resolved, pre_fork_failures = Rerunner.new(rerun: @rerun, out: @out).resolve(report.no_verdict)
      score = Decision.score_of(report, resolved)
      Printer.new(@out).print(report, resolved, pre_fork_failures, score)
      Decision.new(threshold: @threshold).decide!(resolved, pre_fork_failures, score)
      score
    end
  end

  # The full run: removes any report left from an earlier run, runs Mutineer
  # through the injected `runner`, and gates whatever it wrote. A stale
  # report is never read, because nothing is left at `path` for `Gate` to
  # find unless this run's own `runner` call wrote it.
  class Run
    def initialize(path, runner:, rerun:, out: $stdout, threshold: THRESHOLD)
      @path = path
      @runner = runner
      @gate = Gate.new(path, rerun:, out:, threshold:)
    end

    def call
      FileUtils.rm_f(@path)
      output, status = @runner.call
      raise Decision::Failure, "mutineer failed: #{output}" unless status.success? && File.exist?(@path)

      @gate.call
    end
  end

  # Shells out to the real Mutineer, for the CLI tail below. `call` runs the
  # first, full pass; `rerun` (the shape `Gate` expects) runs one subject
  # alone, single worker, against the same Mutineer arguments.
  class Mutineer
    def initialize(args, root: Dir.pwd)
      @args = args
      @root = root
    end

    def call(output)
      Open3.capture2e("bundle", "exec", "mutineer", "run", *@args, "--format", "json", "--output", output, chdir: @root)
    end

    def rerun(subject, ids)
      path = File.join(Dir.mktmpdir("mutation-rerun"), "report.json")
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      call_only(subject, path)
      seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      [verdicts_of(JSON.parse(File.read(path)), ids), seconds]
    end

    private

    def call_only(subject, path)
      Open3.capture2e("bundle", "exec", "mutineer", "run", *@args, "--only", subject, "--jobs", "1", "--format", "json", "--output", path, chdir: @root)
    end

    def verdicts_of(report, ids)
      survived = report.fetch("survivors", []).map { |mutant| mutant["id"] }
      unresolved = report.fetch("no_verdict", []).map { |mutant| mutant["id"] }
      ids.to_h { |id| [id, status_of(id, survived, unresolved)] }
    end

    def status_of(id, survived, unresolved)
      return "survived" if survived.include?(id)
      return "no_verdict" if unresolved.include?(id)

      "killed"
    end
  end
end

if $PROGRAM_NAME == __FILE__
  require "open3"

  args = ARGV.dup
  args.shift if args.first == "run"
  output = args[args.index("--output") + 1]
  threshold = Integer(args[args.index("--threshold") + 1])
  mutineer = MutationVerdicts::Mutineer.new(args[(args.index("--") + 1)..])

  begin
    MutationVerdicts::Run.new(output, runner: -> { mutineer.call(output) }, rerun: mutineer.method(:rerun), threshold:).call
  rescue MutationVerdicts::Decision::Failure => e
    warn e.message
    exit 1
  end
end
