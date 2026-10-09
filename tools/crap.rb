require "json"
require "open3"
require "prism"

module Crap
  DECISIONS = [
    Prism::IfNode, Prism::UnlessNode, Prism::WhileNode, Prism::UntilNode, Prism::ForNode,
    Prism::WhenNode, Prism::InNode, Prism::RescueNode, Prism::AndNode, Prism::OrNode
  ].freeze

  Score = Struct.new(:name, :file, :first_line, :last_line, :complexity, :coverage, keyword_init: true) do
    def crap
      (complexity**2 * (1 - coverage)**3 + complexity).round(1)
    end
  end

  # The new-side start line and line count of one zero-context diff hunk.
  HUNK = /\A@@ -\S+ \+(\d+)(?:,(\d+))? @@/

  # One hunk of a zero-context diff: the file, its new-side span and its body lines.
  Hunk = Struct.new(:file, :start, :count, :body) do
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
    collect(Prism.parse(source).value, [], file, [])
  end

  def collect(node, scope, file, found)
    case node
    when Prism::ClassNode, Prism::ModuleNode
      scope += [node.constant_path.slice]
    when Prism::DefNode
      separator = node.receiver ? "." : "#"
      found << { name: "#{scope.join("::")}#{separator}#{node.name}", file: file,
                 first_line: node.location.start_line, last_line: node.location.end_line,
                 complexity: 1 + decisions(node.body) }
    end
    node.compact_child_nodes.each { |child| collect(child, scope, file, found) }
    found
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
    JSON.parse(resultset_json).values.each_with_object({}) do |run, files|
      run.fetch("coverage").each do |path, entry|
        lines = entry.is_a?(Hash) ? entry.fetch("lines") : entry
        files[path] = files.key?(path) ? merge(files[path], lines) : lines
      end
    end
  end

  def merge(left, right)
    left.zip(right).map { |a, b| a.nil? && b.nil? ? nil : [a.to_i, b.to_i].max }
  end

  def method_coverage(found, lines)
    return 0.0 unless lines

    range = found[:first_line] == found[:last_line] ? [found[:first_line]] : ((found[:first_line] + 1)..(found[:last_line] - 1)).to_a
    relevant = range.map { |number| lines[number - 1] }.compact
    return 1.0 if relevant.empty?

    relevant.count(&:positive?).fdiv(relevant.size)
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
    
    def initialize(argv, root:, out: $stdout, git: ->(*args) { Open3.capture2("git", "-C", root, *args).first })
      @argv = argv.dup
      @root = root
      @out = out
      @git = git
      @missing_value = false
    end

    def run
      return usage if @argv.include?("--help") || @argv.include?("-h")

      threshold = option("--threshold", "30").to_f
      since = option("--since", nil)
      resultset = File.join(@root, option("--coverage", "coverage/.resultset.json"))
      return usage(2) if @missing_value || @argv.any? { |argument| argument.start_with?("-") }

      paths = @argv.empty? ? Dir.glob(%w[lib/**/*.rb app/**/*.rb tools/**/*.rb], base: @root) : @argv
      coverage = File.exist?(resultset) ? Crap.line_coverage(File.read(resultset)) : {}
      changed = since ? Crap.changed_lines(@git.call("diff", "--unified=0", since, "--", "*.rb")) : nil
      scores = paths.flat_map { |path| scores_for(path, coverage) }
      scores = scores.select { |score| Crap.touched?(score.to_h, changed) } if changed
      report(scores.sort_by { |score| -score.crap }, threshold)
    end

    private

    def usage(code = 0)
      @out.puts USAGE
      code
    end

    def option(flag, default)
      index = @argv.index(flag)
      return default unless index

      value = @argv[index + 1]
      if value.nil? || value.start_with?("--")
        @argv.delete_at(index)
        @missing_value = true
        return default
      end

      @argv.delete_at(index)
      @argv.delete_at(index)
    end

    def scores_for(path, coverage)
      absolute = File.expand_path(path, @root)
      Crap.methods_in_source(File.read(absolute), path).map do |found|
        Score.new(**found, coverage: Crap.method_coverage(found, coverage[absolute]))
      end
    end

    def report(scores, threshold)
      @out.puts format("%-7s %-10s %-9s %s", "CRAP", "complexity", "coverage", "method")
      scores.each do |score|
        @out.puts format("%-7.1f %-10d %-9s %s  %s:%d", score.crap, score.complexity,
                         "#{(score.coverage * 100).round}%", score.name, score.file, score.first_line)
      end
      over = scores.count { |score| score.crap > threshold }
      @out.puts "#{scores.size} methods, #{over} above CRAP #{threshold.to_i}"
      over.zero? ? 0 : 1
    end
  end
end
