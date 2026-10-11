require "json"
require "open3"
require "prism"

# Scores each Ruby method by CRAP: its complexity weighed against its line coverage.
module Crap
  DECISIONS = [
    Prism::IfNode, Prism::UnlessNode, Prism::WhileNode, Prism::UntilNode, Prism::ForNode,
    Prism::WhenNode, Prism::InNode, Prism::RescueNode, Prism::AndNode, Prism::OrNode
  ].freeze

  # One method's place, complexity, coverage and CRAP score.
  Score = Struct.new(:name, :file, :first_line, :last_line, :complexity, :coverage)

  # How a score is computed and printed.
  class Score
    def crap
      (complexity**2 * (1 - coverage)**3 + complexity).round(1)
    end

    def row
      format("%-7.1f %-10d %-9s %s  %s:%d", crap, complexity, "#{(coverage * 100).round}%", name, file, first_line)
    end
  end

  # The new-side start line and line count of one zero-context diff hunk.
  HUNK = /\A@@ -\S+ \+(\d+)(?:,(\d+))? @@/

  # One hunk of a zero-context diff: the file, its new-side span and its body lines.
  Hunk = Struct.new(:file, :start, :count, :body)

  # How a hunk maps to the code lines it changed.
  class Hunk
    def span = count.zero? ? [start] : (start...(start + count)).to_a

    def added = body.select { |line| line.start_with?("+") }

    def code_removed? = body.any? { |line| line.start_with?("-") && !Crap.comment?(line) }

    def code_lines
      return span if body.empty?

      kept = span.zip(added).filter_map { |number, line| number unless Crap.comment?(line.to_s) }
      (kept.empty? && code_removed?) ? [start] : kept
    end
  end

  module_function

  def formula(complexity, coverage)
    (complexity**2 * (1 - coverage)**3 + complexity).round(1)
  end

  def methods_in_source(source, file)
    collect(Prism.parse(source).value, [], file)
  end

  def collect(node, scope, file)
    case node
    when Prism::ClassNode, Prism::ModuleNode then scope += [node.constant_path.slice]
    when Prism::DefNode then own = [method_entry(node, scope, file)]
    end
    Array(own) + node.compact_child_nodes.flat_map { |child| collect(child, scope, file) }
  end

  def method_entry(node, scope, file)
    separator = node.receiver ? "." : "#"
    location = node.location
    { name: "#{scope.join("::")}#{separator}#{node.name}", file: file,
      first_line: location.start_line, last_line: location.end_line, complexity: 1 + decisions(node.body) }
  end

  def decisions(node)
    return 0 unless node

    own = decision?(node) ? 1 : 0
    own + node.compact_child_nodes.sum { |child| decisions(child) }
  end

  def decision?(node)
    return true if DECISIONS.any? { |kind| node.is_a?(kind) }
    return node.safe_navigation? if node.is_a?(Prism::CallNode)

    node.class.name.end_with?("OrWriteNode", "AndWriteNode")
  end

  def line_coverage(resultset_json)
    JSON.parse(resultset_json).values.map { |run| run_lines(run) }.reduce({}) { |files, lines| combine(files, lines) }
  end

  def line_coverage_file(path) = File.exist?(path) ? line_coverage(File.read(path)) : {}

  def run_lines(run) = run.fetch("coverage").transform_values { |entry| entry.is_a?(Hash) ? entry.fetch("lines") : entry }

  def combine(files, lines) = files.merge(lines) { |_path, left, right| merge(left, right) }

  def merge(left, right)
    left.zip(right).map { |hits| hits.compact.max }
  end

  def method_coverage(found, lines)
    return 0.0 unless lines

    relevant = measured_lines(found).filter_map { |number| lines[number - 1] }
    return 1.0 if relevant.empty?

    relevant.count(&:positive?).fdiv(relevant.size)
  end

  def measured_lines(found)
    first, last = found.values_at(:first_line, :last_line)
    (first == last) ? [first] : ((first + 1)..(last - 1)).to_a
  end

  def changed_lines(diff)
    hunks(diff).each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |hunk, changed|
      changed[hunk.file].concat(hunk.code_lines)
    end
  end

  def hunks(diff)
    file = nil
    diff.each_line.with_object([]) do |line, found|
      file = target(line) || file
      add_hunk_line(found, file, line)
    end
  end

  def add_hunk_line(found, file, line)
    header = line.match(HUNK)
    return found << Hunk.new(file, header[1].to_i, (header[2] || 1).to_i, []) if header

    found.last.body << line if found.any? && body_line?(line)
  end

  def target(line) = line.start_with?("+++ ") ? line.sub(%r{\A\+\+\+ (b/)?}, "").strip : nil

  def body_line?(line) = line.match?(/\A[+-]/) && !line.match?(%r{\A(\+\+\+ |--- (a/|/dev/null))})

  def comment?(line)
    code = line[1..].to_s.strip
    code.empty? || code.start_with?("#")
  end

  def touched?(found, changed)
    (changed[found[:file]] || []).any? { |number| number.between?(found[:first_line], found[:last_line]) }
  end

  # The flags, paths and help request of one bin/crap call.
  Arguments = Data.define(:values, :paths, :help)

  # How a bin/crap call reads its flags and paths.
  class Arguments
    FLAGS = { "--threshold" => "30", "--since" => nil, "--coverage" => "coverage/.resultset.json" }.freeze
    HELP = %w[--help -h].freeze
    MISSING = Object.new.freeze

    def self.parse(argv)
      rest = argv.dup
      values = FLAGS.to_h { |flag, default| [flag, take(rest, flag, default)] }
      new(values:, paths: rest, help: argv.intersect?(HELP))
    end

    def self.take(rest, flag, default)
      index = rest.index(flag) or return default
      value = rest[index + 1]
      return rest.slice!(index, 2).last if value && !value.start_with?("--")

      rest.delete_at(index)
      MISSING
    end

    def invalid? = values.value?(MISSING) || paths.any? { |argument| argument.start_with?("-") }

    def threshold = values.fetch("--threshold").to_f

    def since = values.fetch("--since")

    def coverage = values.fetch("--coverage")
  end

  # The printed table of scores and the exit code it earns.
  Report = Data.define(:scores, :threshold)

  # How the report counts the methods above the threshold.
  class Report
    HEADER = "CRAP    complexity coverage  method"

    def over = scores.count { |score| score.crap > threshold }

    def lines = [HEADER, *scores.map(&:row), "#{scores.size} methods, #{over} above CRAP #{threshold.to_i}"]

    def status = over.zero? ? 0 : 1
  end

  # The bin/crap command: it parses the call, scores the methods and prints the report.
  class CLI
    USAGE = <<~TEXT
      Usage: bin/crap [--threshold N] [--since REF] [--coverage FILE] [PATH]...

      Scores each method by CRAP = complexity² × (1 − coverage)³ + complexity,
      with line coverage from coverage/.resultset.json. Without PATH it scores
      lib/, app/, and tools/. With --since REF it scores only the methods whose
      lines changed since REF.

      Exit codes: 0 no method above the threshold (default 30), 1 at least one above it, 2 an unknown
      option, or --threshold, --since, or --coverage with no value.
    TEXT

    DEFAULT_PATHS = %w[lib/**/*.rb app/**/*.rb tools/**/*.rb].freeze

    def initialize(argv, root:, out: $stdout, git: ->(*args) { Open3.capture2("git", "-C", root, *args).first })
      @arguments = Arguments.parse(argv)
      @root = root
      @out = out
      @git = git
    end

    def run
      return usage if @arguments.help
      return usage(2) if @arguments.invalid?

      report(scores)
    end

    private

    def usage(code = 0)
      @out.puts USAGE
      code
    end

    def paths
      given = @arguments.paths
      given.empty? ? Dir.glob(DEFAULT_PATHS, base: @root) : given
    end

    def line_coverage = Crap.line_coverage_file(File.join(@root, @arguments.coverage))

    def scores
      coverage = line_coverage
      changed_only(paths.flat_map { |path| scores_for(path, coverage) }).sort_by { |score| -score.crap }
    end

    def changed_only(found)
      since = @arguments.since
      since ? touched(found, since) : found
    end

    def touched(found, since)
      changed = Crap.changed_lines(@git.call("diff", "--unified=0", since, "--", "*.rb"))
      found.select { |score| Crap.touched?(score.to_h, changed) }
    end

    def scores_for(path, coverage)
      absolute = File.expand_path(path, @root)
      Crap.methods_in_source(File.read(absolute), path).map do |found|
        Score.new(**found, coverage: Crap.method_coverage(found, coverage[absolute]))
      end
    end

    def report(scores)
      report = Report.new(scores:, threshold: @arguments.threshold)
      @out.puts report.lines
      report.status
    end
  end
end
