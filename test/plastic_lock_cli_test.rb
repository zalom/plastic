require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require_relative "../scripts/lib/lock"
require_relative "../scripts/lib/bridge"

# The one deterministic repair (intent 108, D5) and its CLI entry point.
# Hermetic: store in mktmpdir; bridges under an injected tmp (kwarg for the
# in-process library calls, PLASTIC_TMP for the CLI child process).
class PlasticLockCliTest < Minitest::Test
  CLI = File.expand_path("../scripts/plastic-lock", __dir__)

  def setup
    @tmp = Dir.mktmpdir("plock-tmp")
    @home = Dir.mktmpdir("plock-home")
    @store = File.join(@home, ".plastic", "projects", "demo", "store")
    @intent_dir = File.join(@store, "96--demo")
    FileUtils.mkdir_p(@intent_dir)
    File.write(File.join(@intent_dir, "96--demo.md"), "## Intent\nDemo\n")
    File.write(File.join(File.dirname(@store), "INDEX.md"),
               "## Active\n- [96 — demo](96--demo/96--demo.md)\n\n## Future\n")
  end

  def teardown
    FileUtils.rm_rf(@tmp)
    FileUtils.rm_rf(@home)
  end

  def repair(session = "sess-1")
    Bridge.repair_lock(session, intent_id: "96", intent_dir: @intent_dir,
                       store: @store, name: "demo", tmp: @tmp)
  end

  def cli(*args, session: "sess-1")
    Open3.capture3({ "PLASTIC_TMP" => @tmp, "CLAUDE_CODE_SESSION_ID" => nil },
                   RbConfig.ruby, CLI, *args,
                   "--intent-dir", @intent_dir, "--session", session)
  end

  # --- repair_lock (library) --------------------------------------------------

  def test_repair_is_idempotent_and_rebuilds_both_sides
    2.times do
      report = repair
      assert_equal "repaired", report["status"]
    end
    lock = Lock.read(@intent_dir)
    assert_equal "sess-1", lock["owner_session"]
    bridge = Bridge.read("sess-1", tmp: @tmp)
    refute_nil bridge
    assert_equal "96", bridge.dig("intent", "id")
    assert_equal "sess-1", bridge.dig("lock", "owner_session")
    refute bridge["lock"].key?("pid")
  end

  def test_repair_backs_off_from_a_fresh_foreign_lock
    Lock.acquire(@intent_dir, session: "other")
    report = repair
    assert_equal "held", report["status"]
    assert_equal "other", Lock.read(@intent_dir)["owner_session"]
  end

  def test_repair_reports_stale_foreign_and_points_at_reclaim
    Lock.acquire(@intent_dir, session: "other")
    FileUtils.touch(Lock.path(@intent_dir), mtime: Time.now - 4000)
    report = repair
    assert_equal "stale", report["status"]
    assert_includes report["hint"], "reclaim"
  end

  def test_repair_removes_a_corrupt_lock_and_rebuilds
    File.write(Lock.path(@intent_dir), "{ nope")
    report = repair
    assert_equal "repaired", report["status"]
    assert_equal "sess-1", Lock.read(@intent_dir)["owner_session"]
  end

  def test_repair_migrates_legacy_tmp_only_pid_lock_state
    # Legacy world: a /tmp bridge with a pid-stamped lock block and NO
    # delivery.lock file (pre-108). Repair builds the durable file from disk
    # truth and rewrites the cache without a pid.
    legacy = {
      "session" => "sess-1",
      "intent" => { "id" => "96", "dir" => "96--demo", "store" => @store,
                    "name" => "demo" },
      "build" => { "stage" => "why", "auto" => false },
      "lock" => { "owner_session" => "sess-1", "pid" => 12345,
                  "acquired_at" => "2026-07-01T00:00:00Z", "host" => "old" },
    }
    Bridge.write("sess-1", legacy, tmp: @tmp)
    report = repair
    assert_equal "repaired", report["status"]
    assert File.exist?(Lock.path(@intent_dir))
    bridge = Bridge.read("sess-1", tmp: @tmp)
    refute bridge["lock"].key?("pid"), "migration strips the legacy pid"
  end

  def test_repair_preserves_the_armed_auto_flag
    legacy = {
      "session" => "sess-1",
      "intent" => { "id" => "96", "dir" => "96--demo", "store" => @store,
                    "name" => "demo" },
      "build" => { "stage" => "why", "auto" => true },
    }
    Bridge.write("sess-1", legacy, tmp: @tmp)
    repair
    assert_equal true, Bridge.read("sess-1", tmp: @tmp).dig("build", "auto")
  end

  # --- CLI verbs ---------------------------------------------------------------

  def test_cli_status_reports_lock_and_bridge
    Lock.acquire(@intent_dir, session: "sess-1")
    out, _err, st = cli("status")
    assert st.success?
    assert_includes out, "sess-1"
    assert_includes out, "delivery"
  end

  def test_cli_fix_is_idempotent
    out1, _e1, st1 = cli("fix")
    out2, _e2, st2 = cli("fix")
    assert st1.success? && st2.success?
    assert File.exist?(Lock.path(@intent_dir))
    assert_includes out1, "repaired"
    assert_includes out2, "repaired"
  end

  def test_cli_fix_exits_nonzero_when_held_elsewhere
    Lock.acquire(@intent_dir, session: "other")
    _out, err, st = cli("fix")
    refute st.success?
    assert_includes err, "held"
  end

  def test_cli_release_clears_the_lock
    Lock.acquire(@intent_dir, session: "sess-1")
    _out, _err, st = cli("release")
    assert st.success?
    refute File.exist?(Lock.path(@intent_dir))
  end

  def test_cli_reclaim_takes_over_a_stale_lock_with_audit
    Lock.acquire(@intent_dir, session: "other")
    FileUtils.touch(Lock.path(@intent_dir), mtime: Time.now - 4000)
    _out, _err, st = cli("reclaim")
    assert st.success?
    assert_equal "sess-1", Lock.read(@intent_dir)["owner_session"]
    assert_includes File.read(File.join(@intent_dir, "savepoint.md")), "takeover"
  end

  def test_cli_reclaim_refuses_a_fresh_foreign_lock
    Lock.acquire(@intent_dir, session: "other")
    _out, err, st = cli("reclaim")
    refute st.success?
    assert_includes err, "back off"
    assert_equal "other", Lock.read(@intent_dir)["owner_session"]
  end

  def test_cli_delegate_registers_a_subagent_session
    Lock.acquire(@intent_dir, session: "sess-1")
    _out, _err, st = cli("delegate", "--delegate", "sub-1")
    assert st.success?
    assert_includes Lock.read(@intent_dir)["delegates"], "sub-1"
  end

  def test_cli_delegate_refused_for_non_owner
    Lock.acquire(@intent_dir, session: "other")
    _out, err, st = cli("delegate", "--delegate", "sub-1")
    refute st.success?
    assert_includes err, "owner"
  end
end
