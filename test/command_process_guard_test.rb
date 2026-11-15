# frozen_string_literal: true

require_relative "test_helper"
require_relative "child_process_guard_test"
require "prism"

# Outside the core acceptance documents, no test starts a command in a child process.
class CommandProcessGuardTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  ALLOWED = %w[
    test/varar/**/*.rb test/cli/**/*.rb test/support/**/*.rb test/runtime_bundle_test.rb test/release_build_test.rb
    test/install_sh_*.rb test/installer_*.rb test/installer_release/**/*.rb test/command_process_guard_test.rb
  ].freeze
  SUPPORT_FILES = %w[kernel_command two_homes delivered_homes].freeze

  # What a source file does that starts a command in a child process.
  class Reaches < Prism::Visitor
    attr_reader :found

    def initialize
      super
      @found = []
      @starting = 0
    end

    def visit_constant_read_node(node)
      @found << :kernel_command if node.name == :KernelCommand
      super
    end

    def visit_string_node(node)
      @found << :launcher if launcher_string?(node)
      @found << :support if SUPPORT_FILES.any? { |name| node.unescaped.end_with?("varar/support/#{name}") }
      super
    end

    def visit_call_node(node)
      @found << :launcher if @starting.positive? && joins_launcher?(node)
      starter = starter?(node)
      @starting += 1 if starter
      super
      @starting -= 1 if starter
    end

    private

    def launcher_string?(node) = @starting.positive? && node.unescaped == "exe/plastic"

    def starter?(node)
      receiver = node.receiver
      receiver.is_a?(Prism::ConstantReadNode) ? %i[ChildProcess Open3].include?(receiver.name) : %i[system spawn].include?(node.name)
    end

    def joins_launcher?(node)
      node.name == :join && node.arguments && %w[exe plastic].all? { |part| strings(node).include?(part) }
    end

    def strings(node) = node.arguments.arguments.grep(Prism::StringNode).map(&:unescaped)
  end

  def reaches(source) = Reaches.new.tap { |visitor| Prism.parse(source).value.accept(visitor) }.found.uniq

  def starts_command?(source) = reaches(source).any?

  def scanned_files
    allowed = ALLOWED.flat_map { |pattern| Dir[File.join(ROOT, pattern)] }
    Dir[File.join(ROOT, "test", "**", "*.rb")] - allowed
  end

  def test_the_scan_reads_a_list_of_test_files_that_is_not_empty
    refute_empty scanned_files
  end

  def test_the_detector_finds_a_read_of_kernel_command
    assert starts_command?("KernelCommand.new(home).command")
  end

  def test_the_detector_finds_a_require_of_a_support_file_of_the_acceptance_documents
    assert starts_command?(%(require_relative "varar/support/two_homes"))
  end

  def test_the_detector_finds_the_launcher_path_written_as_a_string_when_a_process_starts
    assert starts_command?(%(ChildProcess.capture3("ruby", "exe/plastic", "version")))
  end

  def test_the_detector_finds_the_launcher_path_written_as_parts_of_a_join_when_a_process_starts
    assert starts_command?(%(ChildProcess.capture3(File.join(root, "exe", "plastic"), "version")))
  end

  def test_the_detector_leaves_alone_a_name_written_inside_a_string_and_a_launcher_path_that_starts_nothing
    assert_equal [false, false], [starts_command?(%(text = "KernelCommand"\nputs text)), starts_command?(%(File.exist?("exe/plastic")))]
  end

  def test_no_test_outside_the_allowed_list_starts_a_command_in_a_child_process
    offenders = scanned_files.sort.select { |path| starts_command?(File.read(path)) }.map { |path| path.delete_prefix("#{ROOT}/") }

    assert_empty offenders, "run these commands through the plastic helper, in the test's own process"
  end
end
