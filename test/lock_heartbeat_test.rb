require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require_relative "../scripts/lib/lock"
require_relative "../scripts/lib/bridge"

# Lease heartbeat wiring (intent 108, D1): owner tool activity refreshes the
# delivery.lock mtime through the write-path hooks. Hermetic: bridges live in
# an injected PLASTIC_TMP; the intent store lives in a mktmpdir.
class LockHeartbeatTest < Minitest::Test
  GATE_CHECK = File.expand_path("../scripts/hook-gate-check", __dir__)
  LOCK_GATE = File.expand_path("../scripts/hook-lock-gate", __dir__)

  def setup
    @tmp = Dir.mktmpdir("hb-bridge-tmp")
    @home = Dir.mktmpdir("hb-home")
    @store = File.join(@home, ".plastic", "projects", "demo", "store")
    @intent_dir = File.join(@store, "96--demo")
    FileUtils.mkdir_p(@intent_dir)
    File.write(File.join(@intent_dir, "96--demo.md"), "## Intent\nDemo\n")
    File.write(File.join(File.dirname(@store), "INDEX.md"),
               "## Active\n- [96 — demo](96--demo/96--demo.md)\n\n## Future\n")
    @old = Time.now - 900
    Lock.acquire(@intent_dir, session: "sess-1")
    FileUtils.touch(Lock.path(@intent_dir), mtime: @old)
    Bridge.write("sess-1", bridge_data, tmp: @tmp)
  end

  def teardown
    FileUtils.rm_rf(@tmp)
    FileUtils.rm_rf(@home)
  end

  def bridge_data
    { "session" => "sess-1",
      "intent" => { "id" => "96", "dir" => "96--demo", "store" => @store,
                    "name" => "demo" },
      "build" => { "stage" => "why", "auto" => false } }
  end

  def run_hook(script, file)
    Open3.capture3({ "PLASTIC_TMP" => @tmp, "CLAUDE_CODE_SESSION_ID" => nil },
                   RbConfig.ruby, script, file, "sess-1")
  end

  def test_gate_check_write_refreshes_the_lease
    file = File.join(@intent_dir, "resources", "note.md")
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, "x")
    run_hook(GATE_CHECK, file)
    assert File.mtime(Lock.path(@intent_dir)) > @old,
           "PostToolUse gate-check must heartbeat the owner's lock"
  end

  def test_lock_gate_allow_path_refreshes_the_lease
    file = File.join(@intent_dir, "spec.md")
    run_hook(LOCK_GATE, file)
    assert File.mtime(Lock.path(@intent_dir)) > @old
  end

  def test_foreign_session_write_does_not_refresh_the_lease
    file = File.join(@intent_dir, "spec.md")
    Open3.capture3({ "PLASTIC_TMP" => @tmp, "CLAUDE_CODE_SESSION_ID" => nil },
                   RbConfig.ruby, LOCK_GATE, file, "stranger")
    assert_equal @old.to_i, File.mtime(Lock.path(@intent_dir)).to_i,
                 "a denied stranger must not touch the owner's heartbeat"
  end

  # --- lease semantics against a second session (pure, injected clock) -------

  def test_second_session_refused_while_fresh_reclaim_only_after_ttl
    t0 = Time.now
    refute_nil Bridge.lock_gate_decision(nil, File.join(@intent_dir, "spec.md"),
                                         session: "sess-2", now: t0, ttl: 1800)
    status, _ = Lock.takeover(@intent_dir, session: "sess-2", ttl: 1800, now: t0)
    assert_equal :fresh, status, "takeover refused while the lease is fresh"

    FileUtils.touch(Lock.path(@intent_dir), mtime: t0 - 3600)
    status, data = Lock.takeover(@intent_dir, session: "sess-2", ttl: 1800, now: t0)
    assert_equal :taken, status
    assert_equal "sess-2", data["owner_session"]
  end
end
