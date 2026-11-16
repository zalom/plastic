# frozen_string_literal: true

require_relative "test_helper"
require "prism"

# Outside the core acceptance documents, no test starts a command in a child process.
class CommandProcessGuardTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  ALLOWED = %w[
    test/varar/*.rb test/varar/support/*.rb
    test/cli/launcher_test.rb test/cli/launcher_uninstall_test.rb test/cli/package_bin_test.rb test/cli/release_contract_test.rb
    test/cli/lazy_command_dispatch_test.rb test/cli/retrieval_read_cli_test.rb
    test/runtime_bundle_test.rb test/release_build_test.rb
    test/command_names_guard_test.rb test/kernel_paths_guard_test.rb
    test/install_sh_*.rb test/installer_release/*.rb
    test/support/child_process.rb test/support/install_sh_helper.rb test/support/second_load.rb test/support/second_load_test.rb
    test/command_process_guard_test.rb
  ].freeze
  SUPPORT_FILES = %w[kernel_command two_homes delivered_homes].freeze
  TOOL_WORDS = %w[exe/plastic bin/plastic Plastic::CLI].freeze
  TOOL_JOINS = [%w[exe plastic], %w[bin plastic]].freeze
  FREE_STARTERS = %i[system spawn exec].freeze
  RECEIVER_STARTERS = { ChildProcess: nil, Open3: nil, Kernel: FREE_STARTERS, Process: %i[spawn exec], IO: %i[popen], PTY: %i[spawn] }.freeze

  # What a source file does that starts a command in a child process: it starts some process
  # and it names the tool, in one file.
  class Reaches < Prism::Visitor
    def initialize
      super
      @found = []
    end

    def result = (@found.include?(:start) && @found.include?(:tool) ? [:launcher] : []) + (@found & %i[kernel_command support])

    def visit_constant_read_node(node)
      @found << :kernel_command if node.name == :KernelCommand
      super
    end

    def visit_string_node(node)
      name_text(node.unescaped)
      super
    end

    def visit_x_string_node(node)
      @found << :start
      name_text(node.unescaped)
      super
    end

    def visit_interpolated_x_string_node(node)
      @found << :start
      super
    end

    def visit_call_node(node)
      @found << :start if starter?(node)
      @found << :tool if joins_tool?(node)
      super
    end

    private

    def name_text(text)
      @found << :tool if TOOL_WORDS.any? { |word| text.include?(word) }
      @found << :support if SUPPORT_FILES.any? { |name| text.end_with?("varar/support/#{name}") }
    end

    def starter?(node)
      receiver = node.receiver
      return FREE_STARTERS.include?(node.name) if receiver.nil?
      return false unless receiver.is_a?(Prism::ConstantReadNode) && RECEIVER_STARTERS.key?(receiver.name)

      (names = RECEIVER_STARTERS[receiver.name]).nil? || names.include?(node.name)
    end

    def joins_tool?(node)
      node.name == :join && node.arguments && TOOL_JOINS.any? { |parts| (parts - strings(node)).empty? }
    end

    def strings(node) = node.arguments.arguments.grep(Prism::StringNode).map(&:unescaped)
  end

  def reaches(source) = Reaches.new.tap { |visitor| Prism.parse(source).value.accept(visitor) }.result.uniq

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

  CAUGHT = {
    "Process.spawn" => %(Process.spawn("ruby", "exe/plastic", "status")),
    "Kernel.system" => %(Kernel.system("ruby", "exe/plastic", "status")),
    "Kernel.spawn" => %(Kernel.spawn("ruby", "exe/plastic", "status")),
    "exec" => %(exec("ruby", "exe/plastic", "status")),
    "IO.popen" => %(IO.popen(["ruby", "exe/plastic", "status"]).read),
    "PTY.spawn" => %(PTY.spawn("ruby", "exe/plastic", "status")),
    "backticks" => "`ruby exe/plastic status`",
    "percent x" => "%x(ruby exe/plastic status)",
    "one shell string" => %(system("ruby exe/plastic status")),
    "launcher in a constant" => %(LAUNCHER = File.join(ROOT, "exe", "plastic")\nChildProcess.capture3(LAUNCHER, "status")),
    "launcher by expand_path" => %(ChildProcess.capture3(RbConfig.ruby, File.expand_path("../exe/plastic", __dir__), "status")),
    "launcher by join" => %(ChildProcess.capture3(File.join("exe", "plastic"), "status")),
    "kernel by ruby -e" => %(ChildProcess.capture3(RbConfig.ruby, "-e", "exit Plastic::CLI.call(ARGV)", "status")),
    "packaged bin/plastic" => %(ChildProcess.capture3(File.join(release, "bin", "plastic"), "status")),
    "Open3 with the launcher" => %(Open3.capture3("ruby", "exe/plastic", "status"))
  }.freeze

  LEFT_ALONE = {
    "a start that runs another program" => %(ChildProcess.capture3("git", "status")),
    "a backtick that runs another program" => "`git status`",
    "the launcher named with no start" => %(File.exist?("exe/plastic")),
    "the launcher joined with no start" => %(File.join(root, "bin", "plastic")),
    "the kernel named with no start" => %(Plastic::CLI.call(["status"])),
    "a start named inside a string" => %(text = "Process.spawn exe/plastic")
  }.freeze

  CAUGHT.each do |form, source|
    define_method("test_the_detector_finds_a_start_through_#{form.tr("^a-z", "_")}") { assert starts_command?(source) }
  end

  LEFT_ALONE.each do |form, source|
    define_method("test_the_detector_leaves_alone_#{form.tr("^a-z", "_")}") { refute starts_command?(source) }
  end

  def test_the_allowed_files_are_named_one_by_one
    assert_empty ALLOWED.grep(/\*\*/), "name each allowed file, not a folder"
  end

  def test_no_test_outside_the_allowed_list_starts_a_command_in_a_child_process
    offenders = scanned_files.sort.select { |path| starts_command?(File.read(path)) }.map { |path| path.delete_prefix("#{ROOT}/") }

    assert_empty offenders, "run these commands through the plastic helper, in the test's own process"
  end
end
