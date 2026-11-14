# frozen_string_literal: true

require_relative "test_helper"
require_relative "child_process_guard_test"

# The kernel starts no process. A check, a download or an install step that
# needs one runs as a command the person is given in a `next:` line.
class KernelStartsNoProcessGuardTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SCRIPT_REQUIRE = %r{\A\s*require(?:_relative)?\s+["'][^"']*\bscripts/}

  def starts(source) = ChildProcessGuardTest::Starts.new.tap { |visitor| Prism.parse(source).value.accept(visitor) }.lines

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
    assert_equal [2], script_requires(%(require "json"\nrequire_relative "../../scripts/lib/installer_core"\n))
  end

  def test_the_detector_leaves_a_require_inside_the_kernel
    assert_empty script_requires(%(require_relative "../installations/share"\nrequire "plastic/scripts_table"\n))
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
