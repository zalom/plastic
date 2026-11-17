# frozen_string_literal: true

require_relative "test_helper"
require "prism"
require "tsort"
require "rbconfig"
require_relative "support/child_process"

# The require_relative edges under lib, read with Prism, as paths relative to lib/plastic.
class RequireMap
  LIB = File.expand_path("../lib", __dir__)
  ROOT = File.join(LIB, "plastic")

  def self.files = Dir.glob(File.join(ROOT, "**", "*.rb")).map { |path| relative(path) }

  def self.relative(path) = path.delete_prefix("#{ROOT}/")

  def self.edges = files.flat_map { |from| pairs(from) }

  def self.pairs(from) = requires(from).product([from]).map(&:reverse)

  def self.units(unit) = edges.map { |pair| pair.map(&unit) }.select(&:all?)

  def self.named(pairs) = pairs.map { |from, to| "#{from} -> #{to}" }

  def self.requires(from)
    path = File.join(ROOT, from)
    calls(Prism.parse_file(path).value).filter_map { |call| target(call, path) }
  end

  def self.target(call, path)
    argument = call.arguments&.arguments&.first
    return unless call.name == :require_relative && argument.is_a?(Prism::StringNode)

    relative(File.expand_path("#{argument.unescaped.delete_suffix(".rb")}.rb", File.dirname(path)))
  end

  def self.calls(node) = (node.is_a?(Prism::CallNode) ? [node] : []) + node.compact_child_nodes.flat_map { |child| calls(child) }

  def self.top(path) = path.delete_suffix(".rb").split("/").first

  def self.package(path)
    segments = path.delete_suffix(".rb").split("/")
    segments[1] if segments.first == "graph" && segments.size > 1
  end

  def self.definitions(path) = defs(Prism.parse_file(path).value)

  def self.defs(node) = (node.is_a?(Prism::DefNode) ? [node.name] : []) + node.compact_child_nodes.flat_map { |child| defs(child) }
end

# A directed graph of units: the groups of units that depend on each other in a loop.
class UnitGraph
  include TSort

  def initialize(pairs)
    @children = Hash.new { |hash, key| hash[key] = [] }
    pairs.each do |from, to|
      @children[to]
      @children[from] |= [to] unless from == to
    end
  end

  def tsort_each_node(&) = @children.each_key(&)

  def tsort_each_child(node, &) = @children.fetch(node).each(&)

  def cycles = strongly_connected_components.select { |group| group.size > 1 }
end

# The direction of every require_relative under lib/plastic: the core never
# requires the shell, components form no cycle, and the root file defines nothing.
class RequireDirectionGuardTest < Minitest::Test
  CORE = %w[graph config harnesses workflow workflows code_workflow agent_workflow doctor installations context].freeze
  SHELL = %w[cli commands hooks hook wiring].freeze

  def test_no_core_file_requires_the_shell
    pairs = RequireMap.edges.select { |from, to| CORE.include?(RequireMap.top(from)) && SHELL.include?(RequireMap.top(to)) }

    assert_empty RequireMap.named(pairs)
  end

  def test_components_under_lib_plastic_form_no_cycle
    assert_empty UnitGraph.new(RequireMap.units(RequireMap.method(:top))).cycles
  end

  def test_graph_packages_form_no_cycle
    assert_empty UnitGraph.new(RequireMap.units(RequireMap.method(:package))).cycles
  end

  def test_workflow_base_names_no_workflow
    pairs = RequireMap.edges.select { |from, to| from.match?(%r{\Aworkflow(/|\.rb\z)}) && to.start_with?("workflows/") }

    assert_empty RequireMap.named(pairs)
  end

  def test_root_file_defines_nothing
    assert_empty RequireMap.definitions(File.join(RequireMap::LIB, "plastic.rb"))
  end

  def test_loading_every_file_warns_of_no_circular_require
    script = "Dir.glob(File.join('#{RequireMap::ROOT}', '**', '*.rb')).sort.each { |file| require file }"
    _out, err, = ChildProcess.capture3(RbConfig.ruby, "-w", "-I", RequireMap::LIB, "-e", script)

    assert_empty err.lines.grep(/circular require considered harmful/)
  end
end
