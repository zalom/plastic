# frozen_string_literal: true

require_relative "test_helper"
require_relative "child_process_guard_test"

# The kernel starts no process. A check, a download or an install step that
# needs one runs as a command the person is given in a `next:` line.
class KernelStartsNoProcessGuardTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SCRIPT_REQUIRE = %r{\A[^#\n]*\b(?:require|require_relative|load|autoload)\b[^#\n]*["'/]scripts["'/]}
  KERNEL_STARTERS = ChildProcessGuardTest::STARTERS.merge(
    nil => %i[system spawn exec fork], :Process => %i[spawn exec fork daemon], :Kernel => %i[system spawn exec fork `],
    :PTY => %i[spawn], :File => %i[popen]
  ).freeze

  # The starts of the launching guard, and the forms the kernel must not use besides:
  # fork, daemon, PTY, File.popen, a piped open or read, a rooted ::Open3, and Open3 mixed in.
  class KernelStarts < ChildProcessGuardTest::Starts
    private

    def starts?(node)
      name = constant_name(node.receiver)
      name == :Open3 || KERNEL_STARTERS.fetch(node.receiver && name, []).include?(node.name) || piped?(node, name) || mixes_in_open3?(node)
    end

    def mixes_in_open3?(node)
      %i[include extend].include?(node.name) && node.arguments&.arguments&.any? { |argument| constant_name(argument) == :Open3 }
    end

    def constant_name(receiver)
      case receiver
      when Prism::ConstantReadNode then receiver.name
      when Prism::ConstantPathNode then receiver.name if receiver.parent.nil?
      end
    end

    def piped?(node, receiver_name)
      reads = %i[open read].include?(node.name) && [nil, :IO].include?(receiver_name)
      reads && pipe_literal?(node.arguments&.arguments&.first)
    end

    def pipe_literal?(argument)
      literal = argument.is_a?(Prism::InterpolatedStringNode) ? argument.parts.first : argument
      literal.is_a?(Prism::StringNode) && literal.unescaped.start_with?("|")
    end
  end

  def starts(source) = KernelStarts.new.tap { |visitor| Prism.parse(source).value.accept(visitor) }.lines

  def script_requires(source) = source.lines.each_index.select { |index| source.lines[index].match?(SCRIPT_REQUIRE) }.map(&:succ)

  def scanned_files = Dir[File.join(ROOT, "lib", "**", "*.rb")] + [File.join(ROOT, "exe", "plastic")]

  def test_the_scan_reads_the_kernel_files_and_the_launcher
    assert_includes scanned_files, File.join(ROOT, "exe", "plastic")
    assert_operator scanned_files.size, :>, 100
  end

  def test_the_detector_finds_a_process_started_in_a_kernel_file
    assert_equal [1, 2], starts(%(system("ruby")\nOpen3.capture2("git")\n))
  end

  def test_the_detector_leaves_a_command_written_into_a_next_line
    assert_empty starts(%(offers = "ruby scripts/install-release --switch 2.0.3"\n))
  end

  def test_the_detector_finds_a_require_of_scripts
    assert_equal [2], script_requires(%(require "json"\nrequire_relative "../../scripts/lib/installer_release"\n))
  end

  def test_the_detector_leaves_a_require_inside_the_kernel
    assert_empty script_requires(%(require_relative "../installations/share"\nrequire "plastic/scripts_table"\n))
  end

  STARTING_FORMS = {
    "fork" => ["fork { work }", "fork_report(1)"],
    "Process.fork" => ["Process.fork", "Process.pid"],
    "Process.daemon" => ["Process.daemon", "Process.clock_gettime(1)"],
    "PTY.spawn" => [%(PTY.spawn("git")), "PTY.winsize(io)"],
    "File.popen" => [%(File.popen("git")), %(File.read("notes.txt"))],
    "open with a pipe" => [%(open("|git status")), %(open("notes.txt"))],
    "IO.read with a pipe" => [%(IO.read("|git status")), %(IO.read("notes.txt"))],
    "::Open3" => [%(::Open3.capture3("git")), %(::Opened.capture3("git"))],
    "include Open3" => [%(include Open3), %(include Comparable)],
    "Kernel backtick" => [%(Kernel.`("git")), %(Kernel.format("%s", name))],
    "backtick" => ["`git status`", %("Run `plastic status` first.")],
    "%x" => ["%x(git status)", %("%x is text")]
  }.freeze

  LOADING_FORMS = {
    "load" => [%(load "scripts/install-release"), %(load "plastic/scripts_table")],
    "autoload" => [%(autoload :Release, "scripts/lib/release"), %(autoload :Table, "plastic/scripts_table")],
    "require with a joined path" => [%(require File.join(root, "scripts", "lib", "release")), %(require File.join(root, "plastic", "table"))]
  }.freeze

  STARTING_FORMS.each do |form, (caught, left)|
    define_method("test_the_detector_finds_#{form.gsub(/\W+/, "_")}") { assert_equal [1], starts(caught) }
    define_method("test_the_detector_leaves_the_sample_beside_#{form.gsub(/\W+/, "_")}") { assert_empty starts(left) }
  end

  LOADING_FORMS.each do |form, (caught, left)|
    define_method("test_the_detector_finds_a_script_through_#{form.gsub(/\W+/, "_")}") { assert_equal [1], script_requires(caught) }
    define_method("test_the_detector_leaves_the_sample_beside_#{form.gsub(/\W+/, "_")}") { assert_empty script_requires(left) }
  end

  def test_no_kernel_file_requires_a_script
    offenders = scanned_files.sort.flat_map do |path|
      script_requires(File.read(path)).map { |line| "#{path.delete_prefix("#{ROOT}/")}:#{line}" }
    end

    assert_empty offenders, "scripts require the kernel, never the reverse"
  end

  def test_no_kernel_file_starts_a_process
    offenders = scanned_files.sort.flat_map do |path|
      starts(File.read(path)).map { |line| "#{path.delete_prefix("#{ROOT}/")}:#{line}" }
    end

    assert_empty offenders, "the kernel prints the command; it does not run it"
  end
end
