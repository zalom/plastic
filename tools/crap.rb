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
    file = nil
    diff.each_line.with_object(Hash.new { |hash, key| hash[key] = [] }) do |line, changed|
      if line.start_with?("+++ ")
        file = line.sub(%r{\A\+\+\+ (b/)?}, "").strip
      elsif (hunk = line.match(/\A@@ -\S+ \+(\d+)(?:,(\d+))? @@/))
        start = hunk[1].to_i
        count = hunk[2] ? hunk[2].to_i : 1
        changed[file].concat(count.zero? ? [start] : (start...(start + count)).to_a)
      end
    end
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
