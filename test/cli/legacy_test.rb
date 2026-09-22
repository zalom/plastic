# frozen_string_literal: true

require_relative "../test_helper"
require "fileutils"
require "tmpdir"
require_relative "../../scripts/lib/cli/legacy"

class CliLegacyTest < Minitest::Test
  class SignalledStatus
    def success? = false

    def exitstatus = nil
  end

  def legacy(status, recorder = [])
    runner = lambda do |path, arguments|
      recorder << [path, arguments]
      status
    end
    Plastic::CLI::Legacy.new(env: {}, runner: runner)
  end

  def test_the_script_path_sits_in_the_package
    path = Plastic::CLI::Legacy.new(env: {}).script_path("install.rb")

    assert_equal File.expand_path("../../scripts/install.rb", __dir__), path
  end

  def test_the_package_root_can_be_injected_through_the_environment
    legacy = Plastic::CLI::Legacy.new(env: {"PLASTIC_PACKAGE_ROOT" => "/opt/plastic"})

    assert_equal "/opt/plastic/scripts/install.rb", legacy.script_path("install.rb")
  end

  def test_a_clean_run_answers_zero
    assert_equal 0, legacy(0).run("install.rb")
  end

  def test_the_arguments_reach_the_script
    recorder = []
    legacy(0, recorder).run("install.rb", "--claude", "--dry-run")

    assert_equal [["--claude", "--dry-run"]], recorder.map(&:last)
  end

  def test_the_script_path_reaches_the_runner
    recorder = []
    legacy(0, recorder).run("update.rb")

    assert_equal [File.expand_path("../../scripts/update.rb", __dir__)], recorder.map(&:first)
  end

  def test_a_failing_run_answers_its_status
    assert_equal 7, legacy(7).run("install.rb")
  end

  def test_a_run_that_exits_three_raises_a_refusal
    error = assert_raises(Plastic::CLI::Command::Refusal) { legacy(3).run("uninstall.rb") }

    assert_includes error.message, "uninstall.rb"
  end

  def test_verification_findings_are_not_owner_refusals
    assert_equal 3, legacy(3).run("verify-intent")
  end

  def test_an_unimplemented_runner_verb_is_not_an_owner_refusal
    assert_equal 3, legacy(3).run("runner")
  end

  def test_a_run_that_exits_two_answers_two_rather_than_refusing
    assert_equal 2, legacy(2).run("install.rb")
  end

  # The default runner is the one seam no other test exercises, because every
  # other case injects a runner. It spawns a real Ruby child, so these two run a
  # script written to a temporary package root and read the status back.
  def package_with(script, body)
    dir = Dir.mktmpdir("plastic-legacy-runner")
    FileUtils.mkdir_p(File.join(dir, "scripts"))
    File.write(File.join(dir, "scripts", script), body)
    dir
  end

  def test_the_default_runner_hands_back_a_childs_exit_code
    dir = package_with("ok.rb", "exit 0\n")

    assert_equal 0, Plastic::CLI::Legacy.new(env: {"PLASTIC_PACKAGE_ROOT" => dir}).run("ok.rb")
  ensure
    FileUtils.remove_entry(dir)
  end

  def test_the_default_runner_turns_a_childs_refusal_into_a_refusal
    dir = package_with("refuse.rb", "exit 3\n")
    legacy = Plastic::CLI::Legacy.new(env: {"PLASTIC_PACKAGE_ROOT" => dir})

    assert_raises(Plastic::CLI::Command::Refusal) { legacy.run("refuse.rb") }
  ensure
    FileUtils.remove_entry(dir)
  end

  def test_a_status_with_no_exit_code_reads_as_a_plain_failure
    assert_equal Plastic::CLI::Command::FAILED, Plastic::CLI::Legacy.exit_code(SignalledStatus.new)
  end

  def test_the_default_runner_reports_a_signalled_child_as_a_failure
    dir = package_with("killed.rb", %(Process.kill("KILL", Process.pid)\n))

    assert_equal Plastic::CLI::Command::FAILED,
      Plastic::CLI::Legacy.new(env: {"PLASTIC_PACKAGE_ROOT" => dir}).run("killed.rb")
  ensure
    FileUtils.remove_entry(dir)
  end
end

# A captured child refuses exactly as a passed-through one does: exit 3 is the
# owner's, and it travels as a Refusal rather than as output to parse.
class LegacyCaptureRefusalTest < Minitest::Test
  def capture_with(status)
    runner = lambda { |_path, _arguments, capture: false| capture ? ["", status] : status }
    Plastic::CLI::Legacy.new(env: {}, runner: runner).capture("doctor.rb")
  end

  def test_exit_three_travels_as_a_refusal
    error = assert_raises(Plastic::CLI::Command::Refusal) { capture_with(Plastic::CLI::Command::REFUSED) }
    assert_includes error.message, "needs the owner"
  end

  def test_every_other_status_comes_back_with_the_output
    assert_equal ["", 1], capture_with(1)
  end
end

# The shipped runner, not an injected one: the capture branch really spawns the
# child and hands back what it printed.
class LegacyDefaultRunnerCaptureTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("plastic-default-runner")
    @script = File.join(@dir, "say.rb")
    File.write(@script, "puts ARGV.join(' '); exit 0\n")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_capture_returns_the_childs_stdout_and_status
    out, status = Plastic::CLI::Legacy::DEFAULT_RUNNER.call(@script, ["hello", "there"], capture: true)

    assert_equal "hello there\n", out
    assert_equal 0, status
  end

  def test_capture_reports_a_failing_childs_status
    File.write(@script, "exit 4\n")
    out, status = Plastic::CLI::Legacy::DEFAULT_RUNNER.call(@script, [], capture: true)

    assert_equal "", out
    assert_equal 4, status
  end

  def test_without_capture_it_answers_with_the_status_alone
    assert_equal 0, Plastic::CLI::Legacy::DEFAULT_RUNNER.call(@script, [])
  end
end
