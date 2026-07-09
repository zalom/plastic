require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require_relative "../scripts/lib/db"
require_relative "../scripts/lib/bridge"

# The one deterministic repair (intent 108, D5) and its CLI entry point,
# cut over to `lock_leases` in intent 41 ACTION_10. Hermetic: store in
# mktmpdir; the CLI child process needs no ambient session id (it is passed
# explicitly via --session), so no tmp/store env injection is needed at all
# (store resolution is derived from --intent-dir, which is always explicit).
class PlasticLockCliTest < Minitest::Test
  CLI = File.expand_path("../scripts/plastic-lock", __dir__)

  def setup
    @home = Dir.mktmpdir("plock-home")
    @store = File.join(@home, ".plastic", "projects", "demo", "store")
    @intent_dir = File.join(@store, "96--demo")
    FileUtils.mkdir_p(@intent_dir)
    File.write(File.join(@intent_dir, "96--demo.md"), "## Intent\nDemo\n")
    File.write(File.join(File.dirname(@store), "INDEX.md"),
               "## Active\n- [96 — demo](96--demo/96--demo.md)\n\n## Future\n")
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def store_home
    File.dirname(@store)
  end

  def conn
    Plastic::DB.connect(store_home)
  end

  def lease_current
    Plastic::DB::Leases.current(conn, "96")
  end

  def acquire(session:, now: Time.now)
    Plastic::DB::Leases.acquire(conn, "96", session: session, host: "h", now: now)
  end

  def repair(session = "sess-1")
    Bridge.repair_lock(session, intent_id: "96", intent_dir: @intent_dir,
                       store: @store, name: "demo")
  end

  def cli(*args, session: "sess-1")
    Open3.capture3({ "CLAUDE_CODE_SESSION_ID" => nil },
                   RbConfig.ruby, CLI, *args,
                   "--intent-dir", @intent_dir, "--session", session)
  end

  # --- repair_lock (library) --------------------------------------------------

  def test_repair_is_idempotent_and_rebuilds_both_sides
    2.times do
      report = repair
      assert_equal "repaired", report["status"]
    end
    lease = lease_current
    assert_equal "sess-1", lease["owner_session"]
    row = Plastic::DB::Sessions.active_for(conn, session: "sess-1--96", cwd: nil)
    refute_nil row
    assert_equal "96", row["active_intent_id"]
    refute lease.key?("pid")
  end

  def test_repair_backs_off_from_a_fresh_foreign_lock
    acquire(session: "other")
    report = repair
    assert_equal "held", report["status"]
    assert_equal "other", lease_current["owner_session"]
  end

  def test_repair_takes_over_an_expired_foreign_lease
    # Leases fail open on expiry: repair may safely reclaim an EXPIRED foreign
    # lease (no more "stale, explicit reclaim only" state to report here).
    acquire(session: "other", now: Time.now - Plastic::DB::Leases::TTL_SECONDS - 100)
    report = repair
    assert_equal "repaired", report["status"]
    assert_includes report["actions"].join(" "), "expired foreign lease reclaimed"
    assert_equal "sess-1", lease_current["owner_session"]
  end

  def test_repair_preserves_the_armed_auto_flag
    Plastic::DB::Sessions.register(conn, session_id: "sess-1--96", host: "h", pid: 1,
                                    cwd: @intent_dir, active_intent_id: "96", auto: true, now: Time.now)
    repair
    row = Plastic::DB::Sessions.active_for(conn, session: "sess-1--96", cwd: nil)
    assert_equal 1, row["auto"]
  end

  # --- CLI verbs ---------------------------------------------------------------

  def test_cli_status_reports_lease
    acquire(session: "sess-1")
    out, _err, st = cli("status")
    assert st.success?
    assert_includes out, "sess-1"
  end

  def test_cli_fix_is_idempotent
    out1, _e1, st1 = cli("fix")
    out2, _e2, st2 = cli("fix")
    assert st1.success? && st2.success?
    refute_nil lease_current
    assert_includes out1, "repaired"
    assert_includes out2, "repaired"
  end

  def test_cli_fix_exits_nonzero_when_held_elsewhere
    acquire(session: "other")
    _out, err, st = cli("fix")
    refute st.success?
    assert_includes err, "held"
  end

  def test_cli_release_clears_the_lease
    acquire(session: "sess-1")
    _out, _err, st = cli("release")
    assert st.success?
    assert_nil lease_current
  end

  def test_cli_reclaim_takes_over_an_expired_lease_with_audit
    # Seed a minimal intents mirror row so the savepoint_events audit stamp
    # (the new home for the old savepoint.md takeover line) actually persists.
    now = Time.now.utc.iso8601
    conn.execute("INSERT INTO intents (intent_id, created_at, updated_at) VALUES (?, ?, ?)",
                 ["96", now, now])
    acquire(session: "other", now: Time.now - Plastic::DB::Leases::TTL_SECONDS - 100)
    _out, _err, st = cli("reclaim")
    assert st.success?
    assert_equal "sess-1", lease_current["owner_session"]

    events = conn.execute(
      "SELECT event_type, actor_session, payload FROM savepoint_events " \
      "WHERE event_type = 'lock/takeover'"
    )
    assert_equal 1, events.length
    event_type, actor_session, payload = events.first
    assert_equal "lock/takeover", event_type
    assert_equal "sess-1", actor_session
    assert_equal "other", JSON.parse(payload)["from"]
  end

  def test_cli_reclaim_refuses_a_fresh_foreign_lock
    acquire(session: "other")
    _out, err, st = cli("reclaim")
    refute st.success?
    assert_includes err, "back off"
    assert_equal "other", lease_current["owner_session"]
  end

  def test_cli_delegate_registers_a_subagent_session
    acquire(session: "sess-1")
    _out, _err, st = cli("delegate", "--delegate", "sub-1")
    assert st.success?
    assert Plastic::DB::Leases.authorized?(conn, "96", session: "sub-1")
  end

  def test_cli_delegate_refused_for_non_owner
    acquire(session: "other")
    _out, err, st = cli("delegate", "--delegate", "sub-1")
    refute st.success?
    assert_includes err, "owner"
  end
end
