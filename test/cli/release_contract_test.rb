# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../scripts/lib/plastic"
require "fileutils"
require "stringio"
require "tmpdir"
require "open3"
require "json"
require "rbconfig"

# An acceptance test of the packaged executable: bin/plastic, run as the
# installed binary would run it, with no RubyGems and no load path but its
# own. One real process start proves the shebang, the load path and
# PLASTIC_PACKAGE_ROOT all resolve; every other case here runs the kernel's
# own public entry in process, which is cheap and proves the same contract
# the executable delegates to.
class CliReleaseContractTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("plastic-release-contract")
    @bin = ENV.fetch("PLASTIC_ACCEPTANCE_BIN") { File.expand_path("../../bin/plastic", __dir__) }
    @result, @error, @status = command("intent", "new", "A sample delivery", "--slug", "sample")
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def command(*args)
    env = { "HOME" => @dir, "PLASTIC_HOME" => File.join(@dir, ".plastic") }
    stdout, stderr, status = Open3.capture3(env, RbConfig.ruby, @bin, *args, "--json", chdir: @dir)
    [JSON.parse(stdout), stderr, status.exitstatus]
  end

  def test_the_real_process_runs_a_shipped_command
    assert_equal 0, @status, @error
    assert_equal "", @error
  end

  def test_the_real_process_writes_the_intent_and_prints_its_folder
    assert_equal ["intent: 1", "printed store/index.json", "printed store/1--sample/1--sample.md",
      "printed store/1--sample/savepoint.md", "printed store/1--sample/graph.json"],
      @result.dig("result", "output")
  end

  def test_the_real_process_names_the_next_step
    assert_equal "plastic next --project global", @result.fetch("next")
  end

  def test_an_unknown_command_is_not_in_this_build_yet
    out, err = StringIO.new, StringIO.new
    code = Plastic::CLI.bin_call(%w[doctor], environment: environment(out:, err:))

    assert_equal 2, code
    assert_equal "plastic doctor is not in this build yet; it lands with its stage\n", err.string
  end

  def test_help_lists_only_the_shipped_commands
    out, err = StringIO.new, StringIO.new
    code = Plastic::CLI.bin_call(["help"], environment: environment(out:, err:))

    assert_equal 0, code
    assert_includes out.string, "intent new"
    refute_includes out.string, "doctor"
  end

  private

  def environment(out:, err:)
    Plastic::CLI::Command::Environment.new(env: { "PLASTIC_HOME" => File.join(@dir, ".plastic") },
      input: StringIO.new, out:, err:, home: @dir, directory: @dir)
  end
end
