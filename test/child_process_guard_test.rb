# frozen_string_literal: true

require_relative "test_helper"
require "prism"

# Every child process a test starts goes through ChildProcess, so it gets a
# clean environment and never the machine's own variables.
class ChildProcessGuardTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  HELPER = File.join(ROOT, "test", "support", "child_process.rb")
  STARTERS = { nil => %i[system spawn exec], Process: %i[spawn exec], IO: %i[popen], Kernel: %i[system spawn exec] }.freeze

  # The lines of a Ruby source that start a process other than through ChildProcess.
  class Starts < Prism::Visitor
    attr_reader :lines

    def initialize
      super
      @lines = []
    end

    def visit_call_node(node)
      @lines << node.location.start_line if starts?(node)
      super
    end

    def visit_x_string_node(node)
      @lines << node.location.start_line
      super
    end

    def visit_interpolated_x_string_node(node)
      @lines << node.location.start_line
      super
    end

    private

    def starts?(node)
      receiver = node.receiver
      name = receiver.name if receiver.is_a?(Prism::ConstantReadNode)
      name == :Open3 || STARTERS.fetch(receiver && name, []).include?(node.name)
    end
  end

  def starts(source) = Starts.new.tap { |visitor| Prism.parse(source).value.accept(visitor) }.lines

  def scanned_files = Dir[File.join(ROOT, "test", "**", "*.rb")] - [HELPER]

  def test_the_scan_reads_a_list_of_test_files_that_is_not_empty
    refute_empty scanned_files
  end

  def test_the_detector_finds_each_way_to_start_a_process
    source = %(Open3.capture3("ls")\nsystem("ls")\nspawn("ls")\nProcess.spawn("ls")\nIO.popen("ls")\nKernel.exec("ls")\n`ls`\n%x(ls \#{dir})\n)

    assert_equal (1..8).to_a, starts(source)
  end

  def test_the_detector_ignores_a_spawn_written_inside_a_string_and_a_call_through_child_process
    source = %(text = %(Open3.capture3("ls"))\nChildProcess.capture3("ls")\nChildProcess.system("ls")\nfile.system_layer\n)

    assert_empty starts(source)
  end

  def test_every_child_process_in_a_test_starts_through_the_clean_environment
    offenders = scanned_files.sort.flat_map do |path|
      starts(File.read(path)).map { |line| "#{path.delete_prefix("#{ROOT}/")}:#{line}" }
    end

    assert_empty offenders, "start these through ChildProcess so they get a clean environment"
  end
end
