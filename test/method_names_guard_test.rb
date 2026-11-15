# frozen_string_literal: true

require "minitest/autorun"
require "prism"

# A method name says what the method does. `run` says nothing, and `take` hides
# whether it locks, captures or reads, so neither names a method. Names that
# start with `test_` are left out. The guard reads the syntax tree, so a name made by
# `def`, `alias`, `alias_method`, `define_method`, a class method or an `attr_*` call counts.
class MethodNamesGuardTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  FOLDERS = %w[lib bin tools scripts exe test].freeze
  RUN = /\Arun!?\z/
  TAKE = /\A(?:\w*_)?take(?:_\w*)?[!?=]?\z/
  SCOPES = [Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode].freeze
  READERS = %i[attr_reader attr_accessor attr].freeze
  NAMING_CALLS = [:alias_method, :define_method, :attr_writer, *READERS].freeze

  def sources
    FOLDERS.flat_map { |folder| Dir[File.join(ROOT, folder, "**", "*")] }.select { |path| ruby_file?(path) }
  end

  def ruby_file?(path)
    File.file?(path) && (path.end_with?(".rb") || File.open(path, &:gets).to_s.match?(/\A#!.*ruby/))
  end

  def nodes(node) = [node, *node.compact_child_nodes.flat_map { |child| nodes(child) }]

  def defined_names(text) = nodes(Prism.parse(text).value).flat_map { |node| names_of(node) }.reject { |name| name.start_with?("test_") }

  def vague_names(text) = defined_names(text).grep(Regexp.union(RUN, TAKE))

  # The names one node brings into being: a `def`, an `alias`, or a call that names a method.
  def names_of(node)
    case node
    when Prism::DefNode then [node.name.to_s]
    when Prism::AliasMethodNode then [node.new_name.unescaped]
    when Prism::CallNode then call_names(node)
    else []
    end
  end

  def call_names(call)
    return [] unless call.receiver.nil? && NAMING_CALLS.include?(call.name)

    suffix = (call.name == :attr_writer) ? "=" : ""
    named_arguments(call).map { |argument| "#{argument.unescaped}#{suffix}" }
  end

  # The names a call hands over: every argument of an `attr_*` call, the first of the others.
  def named_arguments(call)
    arguments = call.arguments&.arguments.to_a
    arguments = arguments.first(1) unless call.name.start_with?("attr")
    arguments.select { |argument| argument.is_a?(Prism::SymbolNode) || argument.is_a?(Prism::StringNode) }
  end

  # A definition counts against the class, module or singleton class whose body holds it directly.
  def repeated_names(text)
    nodes(Prism.parse(text).value).select { |node| SCOPES.any? { |scope| node.is_a?(scope) } }.flat_map { |scope| repeats(defs_of(scope)) }.uniq
  end

  def defs_of(scope)
    body = scope.body
    body = body.statements if body.is_a?(Prism::BeginNode)
    body ? body.body.grep(Prism::DefNode) : []
  end

  def repeats(definitions)
    seen = []
    definitions.filter_map do |definition|
      key = "#{definition.receiver&.slice}.#{definition.name}"
      (definition.name.to_s if seen.include?(key)).tap { seen << key }
    end
  end

  def test_the_sources_are_read_from_the_disk
    refute_empty sources
  end

  def test_the_detector_catches_run_and_take_methods
    sample = "class A\n  def run\n  end\n\n  def self.take_lock(id)\n  end\n  def run!(*args)\n  end\nend\n"

    assert_equal %w[run take_lock run!], vague_names(sample)
  end

  def test_the_detector_catches_a_vague_name_made_by_alias_define_method_a_class_method_or_an_attribute
    samples = {
      "class A\n  alias_method :run, :respond\nend\n" => %w[run],
      "class A\n  alias run respond\nend\n" => %w[run],
      "class A\n  define_method(:run) { 1 }\nend\n" => %w[run],
      "class A\n  def A.run = 1\nend\n" => %w[run],
      "class A\n  attr_reader :take\nend\n" => %w[take],
      "class A\n  attr_accessor :lock, :take_lock\nend\n" => %w[take_lock]
    }

    assert_equal samples.values, samples.keys.map { |sample| vague_names(sample) }
  end

  def test_the_detector_leaves_clear_names_made_the_same_ways_alone
    sample = "class A\n  alias_method :run_report, :respond\n  define_method(:last_run) { 1 }\n  def A.retake = 1\n  attr_reader :taken\nend\n"

    assert_empty vague_names(sample)
  end

  def test_the_detector_catches_a_name_defined_twice_after_a_one_line_class
    sample = "module M\n  class Error < StandardError; end\n\n  def read = 1\n\n  def read = 2\nend\n"

    assert_equal %w[read], repeated_names(sample)
  end

  def test_the_detector_leaves_clear_names_and_test_names_alone
    sample = "class A\n  def run_report\n  end\n\n  def last_run\n  end\n  def test_take_the_lock\n  end\n  def retake\n  end\nend\n"

    assert_empty vague_names(sample)
  end

  def test_the_detector_catches_a_name_defined_twice_in_one_body
    sample = "class A\n  def read\n    1\n  end\n\n  def self.read\n  end\n\n  def read = 2\nend\n"

    assert_equal %w[read], repeated_names(sample)
  end

  def test_the_detector_leaves_the_same_name_in_two_bodies_alone
    sample = "module M\n  class A\n    def read = 1\n  end\n\n  class B\n    def read\n      2\n    end\n  end\n\n  def read = 3\nend\n"

    assert_empty repeated_names(sample)
  end

  def test_no_class_or_module_body_defines_one_name_twice
    offenders = sources.to_h { |path| [path.delete_prefix("#{ROOT}/"), repeated_names(File.read(path))] }.reject { |_, names| names.empty? }

    assert_empty offenders
  end

  def test_no_method_is_named_run_or_take
    offenders = sources.to_h { |path| [path.delete_prefix("#{ROOT}/"), vague_names(File.read(path))] }.reject { |_, names| names.empty? }

    assert_empty offenders
  end
end
