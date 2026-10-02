# frozen_string_literal: true

require "json"
require "fileutils"
require "benchmark"

# The gate's mutation report: reads the JSON Mutineer wrote, re-runs every
# subject a mutant came back without a verdict for, prints what it found, and
# decides whether the step passes. Every collaborator that would otherwise
# shell out (the first run, a re-run) is injected, so a unit test never
# starts Mutineer.
module MutationVerdicts
  THRESHOLD = 75

  # One id a re-run gave a verdict (or not) to, with the subject and
  # location its mutant came from, for printing and deciding alike.
  Resolved = Struct.new(:id, :subject, :file, :line, :status) do
    def killed? = status == "killed"

    def survived? = status == "survived"

    def no_verdict? = status == "no_verdict"

    def location = "#{subject} #{file}:#{line}"
  end

  # What one gate run found: the report Mutineer wrote, what the re-run
  # resolved, what never reached a subject to re-run, and the score those
  # two together add up to. Printer and Decision both read it, so neither
  # carries the other three on its own parameter list.
  Outcome = Struct.new(:report, :resolved, :pre_fork_failures, :score)

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
    def self.ids_of(mutants) = mutants.map { |mutant| mutant.fetch("id") }

    def self.resolved_for(mutant, subject, statuses)
      id = mutant.fetch("id")
      Resolved.new(id, subject, mutant.fetch("file"), mutant.fetch("line"), statuses.fetch(id))
    end

    def initialize(rerun:, out:)
      @rerun = rerun
      @out = out
    end

    def resolve(no_verdict)
      with_subject, without_subject = no_verdict.partition { |mutant| mutant["subject"] }
      [rerun_all(with_subject), without_subject]
    end

    private

    def rerun_all(mutants)
      mutants.group_by { |mutant| mutant.fetch("subject") }.flat_map { |subject, group| rerun_one(subject, group) }
    end

    def rerun_one(subject, mutants)
      klass = self.class
      statuses, seconds = @rerun.call(subject, klass.ids_of(mutants))
      @out.puts format("Re-ran %s alone: %.1fs", subject, seconds)
      mutants.map { |mutant| klass.resolved_for(mutant, subject, statuses) }
    end
  end

  # Decides whether the step passes: no mutant without a subject to re-run,
  # no id still without a verdict after the re-run, and a score at or over
  # the threshold. A report with nothing attempted passes with nothing to
  # mutate.
  class Decision
    # Raised for every way a gate run fails the step: a mutant with nothing
    # to re-run, one still without a verdict after the re-run, or a score
    # under the threshold.
    Failure = Class.new(StandardError)

    def self.score_of(report, resolved)
      killed, survived = tally(report, resolved)
      total = killed + survived
      return 100.0 if total.zero?

      (killed * 100.0 / total).round(1)
    end

    def self.tally(report, resolved)
      summary = report.summary
      [
        summary.fetch("killed") + resolved.count(&:killed?),
        summary.fetch("survived") + resolved.count(&:survived?)
      ]
    end

    def self.pre_fork_message(pre_fork_failures)
      locations = pre_fork_failures.map { |mutant| "#{mutant.fetch("file")}:#{mutant.fetch("line")}" }
      "failed before a worker forked, with no subject to re-run: #{locations.join(", ")}"
    end

    def self.unresolved_message(ids)
      "still without a verdict: #{ids.join(", ")}"
    end

    def initialize(threshold: THRESHOLD)
      @threshold = threshold
    end

    def decide(outcome)
      check_pre_fork(outcome.pre_fork_failures)
      check_unresolved(outcome.resolved)
      check_score(outcome.score)
    end

    private

    def check_pre_fork(pre_fork_failures)
      raise Failure, self.class.pre_fork_message(pre_fork_failures) unless pre_fork_failures.empty?
    end

    def check_unresolved(resolved)
      ids = resolved.select(&:no_verdict?).map(&:id)
      raise Failure, self.class.unresolved_message(ids) unless ids.empty?
    end

    def check_score(score)
      raise Failure, format("mutation score %.1f%% is under the %d%% threshold", score, @threshold) if score < @threshold
    end
  end

  # Prints the gate's own mutation report: every survivor with its diff, and
  # every mutant still without a verdict, named by subject and location.
  class Printer
    def initialize(out)
      @out = out
    end

    def print(outcome)
      @out.puts format("Mutation score: %.1f%%", outcome.score)
      outcome.report.survivors.each { |survivor| print_survivor(survivor) }
      print_unresolved(outcome.resolved, outcome.pre_fork_failures)
    end

    private

    def print_survivor(survivor)
      subject, file, line, diff = survivor.values_at("subject", "file", "line", "diff")
      @out.puts "Survived: #{subject} #{file}:#{line}"
      @out.puts diff
    end

    def print_unresolved(resolved, pre_fork_failures)
      resolved.select(&:no_verdict?).each { |entry| @out.puts "No verdict: #{entry.location}" }
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

      outcome = build_outcome(report)
      verify(outcome)
    end

    private

    def build_outcome(report)
      resolved, pre_fork_failures = Rerunner.new(rerun: @rerun, out: @out).resolve(report.no_verdict)
      Outcome.new(report: report, resolved: resolved, pre_fork_failures: pre_fork_failures, score: Decision.score_of(report, resolved))
    end

    def verify(outcome)
      Printer.new(@out).print(outcome)
      Decision.new(threshold: @threshold).decide(outcome)
      outcome.score
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
    def initialize(args, root: Dir.pwd, runner: ->(*command, chdir:) { Open3.capture2e(*command, chdir:) })
      @args = args
      @root = root
      @runner = runner
    end

    def self.status_of(id, survived, unresolved)
      return "survived" if survived.include?(id)
      return "no_verdict" if unresolved.include?(id)

      "killed"
    end

    def self.ids_of(mutants) = mutants.map { |mutant| mutant["id"] }

    def self.verdicts_of(report, ids)
      survived = ids_of(report.fetch("survivors", []))
      unresolved = ids_of(report.fetch("no_verdict", []))
      ids.to_h { |id| [id, status_of(id, survived, unresolved)] }
    end

    def call(output)
      @runner.call("bundle", "exec", "mutineer", "run", *@args, "--format", "json", "--output", output, chdir: @root)
    end

    def rerun(subject, ids)
      path = File.join(Dir.mktmpdir("mutation-rerun"), "report.json")
      seconds = Benchmark.realtime { call_only(subject, path) }
      [self.class.verdicts_of(JSON.parse(File.read(path)), ids), seconds]
    end

    private

    def call_only(subject, path)
      @runner.call("bundle", "exec", "mutineer", "run", *@args, "--only", subject, "--jobs", "1", "--format", "json", "--output", path, chdir: @root)
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
