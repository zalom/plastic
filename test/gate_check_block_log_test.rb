require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "rbconfig"
require "open3"
require_relative "../scripts/lib/bridge"

# Intent 229: hook-gate-check writes one six-field TSV line per block to
# ~/.plastic/.cache/gate-blocks.log, and a failing write changes nothing about
# the block itself.
class GateCheckBlockLogTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/hook-gate-check", __dir__)
  SESSION = "sess-gate-check-block"

  def setup
    @home = Dir.mktmpdir("gate-check-block-home")
    @store = File.join(@home, ".plastic", "projects", "demo", "store")
    @intent_dir = File.join(@store, "229--demo")
    FileUtils.mkdir_p(@intent_dir)
    File.write(File.join(@intent_dir, "229--demo.md"), "## Intent\nDemo\n")
    @bridge_tmp = Dir.mktmpdir("gate-check-block-tmp")

    @saved_tmp = ENV["PLASTIC_TMP"]
    @saved_session = ENV["CLAUDE_CODE_SESSION_ID"]
    ENV["PLASTIC_TMP"] = @bridge_tmp
    ENV.delete("CLAUDE_CODE_SESSION_ID")

    Bridge.arm_guided(SESSION, intent_id: "229", intent_dir: @intent_dir,
                      store: @store, name: "demo")
  end

  def teardown
    FileUtils.rm_rf(@home)
    FileUtils.rm_rf(@bridge_tmp)
    @saved_tmp.nil? ? ENV.delete("PLASTIC_TMP") : ENV["PLASTIC_TMP"] = @saved_tmp
    @saved_session.nil? ? ENV.delete("CLAUDE_CODE_SESSION_ID") : ENV["CLAUDE_CODE_SESSION_ID"] = @saved_session
  end

  # plan.md with no spec.md present is a gate violation (Bridge.check_gate).
  def blocked_file
    path = File.join(@intent_dir, "plan.md")
    File.write(path, "# Plan\n")
    path
  end

  def run_hook(path)
    Open3.capture3(
      { "HOME" => @home, "PLASTIC_TMP" => @bridge_tmp, "CLAUDE_CODE_SESSION_ID" => nil },
      RbConfig.ruby, SCRIPT, path, SESSION
    )
  end

  def test_block_writes_a_six_field_line
    out, _err, status = run_hook(blocked_file)

    assert_equal 2, status.exitstatus, "plan.md before spec.md must be blocked. hook said: #{out}"
    log = File.join(@home, ".plastic", ".cache", "gate-blocks.log")
    assert File.exist?(log), "a block must be logged"
    f = File.read(log).lines.first.chomp.split("\t", -1)
    assert_equal 6, f.size
    assert_equal "gate-check", f[1]
    assert_equal SESSION, f[2]
    assert_equal "229", f[3]
    assert_includes f[4], "plan.md"
    refute_empty f[5]
  end

  def test_a_failing_block_log_write_does_not_change_the_hook_output
    path = blocked_file
    out_ok, err_ok, st_ok = run_hook(path)

    cache = File.join(@home, ".plastic", ".cache")
    FileUtils.rm_rf(cache)
    File.write(cache, "not a directory\n")

    out_bad, err_bad, st_bad = run_hook(path)

    assert_equal st_ok.exitstatus, st_bad.exitstatus
    assert_equal out_ok, out_bad, "the block JSON must be byte-for-byte identical"
    assert_equal err_ok, err_bad
    assert_equal 2, st_bad.exitstatus
  end
end
