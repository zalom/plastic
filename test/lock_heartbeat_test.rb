require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require_relative "../scripts/lib/db"
require_relative "../scripts/lib/bridge"

# Lease heartbeat wiring (intent 108, D1; cutover intent 41 ACTION_10): owner
# tool activity coarsely renews the delivery lease through the write-path
# hooks. Hermetic: the store lives in a mktmpdir (PLASTIC_STORE_HOME pins it
# for the spawned hooks).
class LockHeartbeatTest < Minitest::Test
  GATE_CHECK = File.expand_path("../scripts/hook-gate-check", __dir__)
  LOCK_GATE = File.expand_path("../scripts/hook-lock-gate", __dir__)

  def setup
    @root = Dir.mktmpdir("hb-root")
    @store = File.join(@root, "store")
    @intent_dir = File.join(@store, "96--demo")
    FileUtils.mkdir_p(@intent_dir)
    File.write(File.join(@intent_dir, "96--demo.md"), "## Intent\nDemo\n")
    File.write(File.join(@root, "INDEX.md"),
               "## Active\n- [96 — demo](96--demo/96--demo.md)\n\n## Future\n")
    # Renewal is COARSE (Plastic::DB::Leases::RENEW_WINDOW_SECONDS = 300): only
    # bumps expires_at once the remaining life is inside that window. Acquire
    # with only ~100s of remaining life so the allow-path renew actually fires
    # and is observable.
    @old = Time.now - (Plastic::DB::Leases::TTL_SECONDS - 100)
    @conn = Plastic::DB.connect(@root)
    Plastic::DB::Leases.acquire(@conn, "96", session: "sess-1", host: "h", now: @old)
    # hook-gate-check resolves the bridge (sessions row) before it renews the
    # lease, exactly like a real armed session would have one.
    Plastic::DB::Sessions.register(@conn, session_id: "sess-1--96", host: "h", pid: 1,
                                    cwd: @intent_dir, active_intent_id: "96", auto: false, now: @old)
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def current_expires_at
    Plastic::DB::Leases.current(@conn, "96")["expires_at"]
  end

  def run_hook(script, file)
    Open3.capture3({ "PLASTIC_STORE_HOME" => @root, "CLAUDE_CODE_SESSION_ID" => nil, "HOME" => @root },
                   RbConfig.ruby, script, file, "sess-1")
  end

  def test_gate_check_write_refreshes_the_lease
    initial_expires = current_expires_at
    file = File.join(@intent_dir, "resources", "note.md")
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, "x")
    run_hook(GATE_CHECK, file)
    refute_equal initial_expires, current_expires_at,
                 "PostToolUse gate-check must renew the owner's lease"
  end

  def test_lock_gate_allow_path_refreshes_the_lease
    initial_expires = current_expires_at
    file = File.join(@intent_dir, "spec.md")
    run_hook(LOCK_GATE, file)
    refute_equal initial_expires, current_expires_at
  end

  def test_foreign_session_write_does_not_refresh_the_lease
    initial_expires = current_expires_at
    file = File.join(@intent_dir, "spec.md")
    Open3.capture3({ "PLASTIC_STORE_HOME" => @root, "CLAUDE_CODE_SESSION_ID" => nil, "HOME" => @root },
                   RbConfig.ruby, LOCK_GATE, file, "stranger")
    assert_equal initial_expires, current_expires_at,
                 "a denied stranger must not touch the owner's lease"
  end

  # --- lease semantics against a second session (pure, injected clock) -------

  def test_second_session_refused_while_fresh_reclaim_only_after_expiry
    t0 = Time.now
    refute_nil Bridge.lock_gate_decision(nil, File.join(@intent_dir, "spec.md"),
                                         session: "sess-2", now: t0, home: @root)
    status, _ = Plastic::DB.lease_takeover(@root, "96", session: "sess-2", now: t0)
    assert_equal :fresh, status, "takeover refused while the lease is fresh"

    status, data = Plastic::DB.lease_takeover(@root, "96", session: "sess-2", now: t0 + 3600)
    assert_equal :taken, status
    assert_equal "sess-2", data["owner_session"]
  end
end
