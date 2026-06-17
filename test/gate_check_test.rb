require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/bridge"

# Regression for intent 52: the savepoint ledger must be written even when no
# bridge file exists and CLAUDE_SESSION_ID is unset. The savepoint is derived
# from the file path, decoupled from bridge resolution.
class GateCheckTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/hook-gate-check", __dir__)

  def setup
    @root = Dir.mktmpdir("gate-check")
    @intent_dir = File.join(@root, "store", "52--x")
    FileUtils.mkdir_p(@intent_dir)
    # Isolated bridge tmp dir so the /tmp scan never sees real bridges.
    @bridge_tmp = Dir.mktmpdir("gate-check-tmp")
    @saved_session = ENV["CLAUDE_SESSION_ID"]
    @saved_plastic_tmp = ENV["PLASTIC_TMP"]
    ENV["PLASTIC_TMP"] = @bridge_tmp
  end

  def teardown
    FileUtils.rm_rf(@root)
    FileUtils.rm_rf(@bridge_tmp)
    restore_env("CLAUDE_SESSION_ID", @saved_session)
    restore_env("PLASTIC_TMP", @saved_plastic_tmp)
  end

  def restore_env(key, saved)
    saved.nil? ? ENV.delete(key) : ENV[key] = saved
  end

  def run_hook(file_path, session: nil)
    # PLASTIC_TMP (set in setup) makes bridge discovery hermetic regardless of cwd.
    env = { "CLAUDE_SESSION_ID" => session, "PLASTIC_TMP" => @bridge_tmp }
    out = IO.popen(env, ["ruby", SCRIPT, file_path], &:read)
    [out, $?]
  end

  def test_savepoint_written_without_bridge_or_session
    # What milestone file: <id>--<slug>.md
    intent_file = File.join(@intent_dir, "52--x.md")
    File.write(intent_file, "## Intent\nx\n")
    spec = File.join(@intent_dir, "spec.md")
    File.write(spec, "spec\n")

    ENV.delete("CLAUDE_SESSION_ID")
    out, status = run_hook(spec)

    assert_equal 0, status.exitstatus, "hook should exit 0, got: #{out}"
    ledger = File.join(@intent_dir, "savepoint.md")
    assert File.exist?(ledger), "savepoint.md must be created"
    assert_includes File.read(ledger), "spec.md created"
  end

  def test_savepoint_idempotent_across_runs
    File.write(File.join(@intent_dir, "52--x.md"), "## Intent\nx\n")
    spec = File.join(@intent_dir, "spec.md")
    File.write(spec, "spec\n")
    ENV.delete("CLAUDE_SESSION_ID")

    run_hook(spec)
    run_hook(spec)
    ledger = File.read(File.join(@intent_dir, "savepoint.md"))
    assert_equal 1, ledger.lines.count { |l| l.include?("spec.md created") }
  end
end
