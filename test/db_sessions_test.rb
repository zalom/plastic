require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "sqlite3"
require "time"

require_relative "../scripts/lib/db"
require_relative "../scripts/lib/db/sessions"
require_relative "../scripts/lib/bridge"

# Hermetic unit tests for Plastic::DB::Sessions (intent 41, ACTION_4): the
# `sessions` table register/update/end verbs, active-for-cwd resolution
# (intent 131 parity), and the `bridge_data`-shaped adapter that is the
# migration spine for the unchanged gate-decision functions. All against a
# Dir.mktmpdir store DB; injected `now:`, no ambient session id, no ENV seam.
class DbSessionsTest < Minitest::Test
  def setup
    @store_home = Dir.mktmpdir("plastic-db-sessions-store")
    @conn = Plastic::DB.connect(@store_home)
  end

  def teardown
    FileUtils.rm_rf(@store_home)
  end

  def t(offset_seconds = 0)
    Time.utc(2026, 7, 9, 12, 0, 0) + offset_seconds
  end

  # --- register ---------------------------------------------------------

  def test_register_creates_one_row
    row = Plastic::DB::Sessions.register(
      @conn, session_id: "sess-1", host: "host-a", pid: 123, cwd: "/tmp/work",
      active_intent_id: "41", auto: true, now: t
    )

    refute_nil row
    assert_equal "sess-1", row["session_id"]
    assert_equal "host-a", row["host"]
    assert_equal 123, row["pid"]
    assert_equal "/tmp/work", row["cwd"]
    assert_equal "41", row["active_intent_id"]
    assert_equal 1, row["auto"]
    assert_equal t.utc.iso8601, row["armed_at"]
    assert_equal t.utc.iso8601, row["last_seen_at"]

    all = @conn.execute("SELECT COUNT(*) FROM sessions").first.first
    assert_equal 1, all
  end

  def test_second_register_same_session_id_updates_in_place_no_duplicate
    Plastic::DB::Sessions.register(
      @conn, session_id: "sess-1", host: "host-a", pid: 1, cwd: "/tmp/a",
      active_intent_id: "41", auto: false, now: t
    )
    row = Plastic::DB::Sessions.register(
      @conn, session_id: "sess-1", host: "host-b", pid: 2, cwd: "/tmp/b",
      active_intent_id: "41", auto: true, now: t(10)
    )

    count = @conn.execute("SELECT COUNT(*) FROM sessions").first.first
    assert_equal 1, count, "a second register for the same session_id must not duplicate the row"

    assert_equal "host-b", row["host"]
    assert_equal "/tmp/b", row["cwd"]
    assert_equal 1, row["auto"]
    # armed_at is set on FIRST register only; it must not advance on re-register.
    assert_equal t.utc.iso8601, row["armed_at"]
    # last_seen_at advances with each register.
    assert_equal t(10).utc.iso8601, row["last_seen_at"]
  end

  def test_register_fails_open_on_nil_conn
    result = Plastic::DB::Sessions.register(
      nil, session_id: "sess-1", host: "h", pid: 1, cwd: "/tmp", active_intent_id: "41",
      auto: true, now: t
    )
    assert_nil result
  end

  # --- update -------------------------------------------------------------

  def test_update_touches_last_seen_at_and_patches_fields
    Plastic::DB::Sessions.register(
      @conn, session_id: "sess-1", host: "host-a", pid: 1, cwd: "/tmp/a",
      active_intent_id: "41", auto: false, now: t
    )

    row = Plastic::DB::Sessions.update(
      @conn, session_id: "sess-1", now: t(30), cwd: "/tmp/new", active_intent_id: "52"
    )

    assert_equal "/tmp/new", row["cwd"]
    assert_equal "52", row["active_intent_id"]
    assert_equal t(30).utc.iso8601, row["last_seen_at"]
    # host/pid untouched (not part of the patch).
    assert_equal "host-a", row["host"]
  end

  def test_update_patches_auto_flag
    Plastic::DB::Sessions.register(
      @conn, session_id: "sess-1", host: "host-a", pid: 1, cwd: "/tmp/a",
      active_intent_id: "41", auto: false, now: t
    )
    row = Plastic::DB::Sessions.update(@conn, session_id: "sess-1", now: t(5), auto: true)
    assert_equal 1, row["auto"]
  end

  def test_update_unknown_session_is_a_noop
    result = Plastic::DB::Sessions.update(@conn, session_id: "does-not-exist", now: t, cwd: "/x")
    assert_nil result
  end

  def test_update_fails_open_on_nil_conn
    assert_nil Plastic::DB::Sessions.update(nil, session_id: "sess-1", now: t, cwd: "/x")
  end

  # --- end ------------------------------------------------------------------

  def test_end_removes_the_row_then_active_for_returns_nil
    Plastic::DB::Sessions.register(
      @conn, session_id: "sess-1", host: "host-a", pid: 1, cwd: "/tmp/a",
      active_intent_id: "41", auto: true, now: t
    )
    Plastic::DB::Sessions.end(@conn, session_id: "sess-1")

    count = @conn.execute("SELECT COUNT(*) FROM sessions").first.first
    assert_equal 0, count
    assert_nil Plastic::DB::Sessions.active_for(@conn, session: "sess-1", cwd: "/tmp/a")
  end

  def test_end_fails_open_on_nil_conn
    assert_nil Plastic::DB::Sessions.end(nil, session_id: "sess-1")
  end

  # --- active_for: strict per-session ownership (intent 90 parity) -----------

  def test_active_for_explicit_session_returns_only_that_sessions_row
    Plastic::DB::Sessions.register(
      @conn, session_id: "sess-1", host: "h", pid: 1, cwd: "/tmp/one",
      active_intent_id: "41", auto: false, now: t
    )
    Plastic::DB::Sessions.register(
      @conn, session_id: "sess-2", host: "h", pid: 2, cwd: "/tmp/two",
      active_intent_id: "52", auto: true, now: t
    )

    row = Plastic::DB::Sessions.active_for(@conn, session: "sess-1", cwd: "/tmp/one")
    assert_equal "sess-1", row["session_id"]
  end

  def test_active_for_never_returns_a_foreign_sessions_row
    Plastic::DB::Sessions.register(
      @conn, session_id: "sess-1", host: "h", pid: 1, cwd: "/tmp/one",
      active_intent_id: "41", auto: false, now: t
    )
    # Asking for a session that owns nothing must resolve to nil, never fall
    # back to the other session's row (fail-open direction is "no bridge",
    # not "borrow someone else's").
    row = Plastic::DB::Sessions.active_for(@conn, session: "sess-2", cwd: "/tmp/one")
    assert_nil row
  end

  # --- active_for: cwd tiering (intent 131 parity) ---------------------------
  #
  # A single real/derived session can legitimately own SEVERAL per-intent rows
  # (one per concurrent auto delivery), mirroring the old per-intent-keyed
  # bridge filename `plastic-<session>--<intent_id>.json`. Sessions stores this
  # the same way: session_id is `"<session>--<intent_id>"` for a per-intent
  # row. A bare `session:` filters to the session's OWN family of rows; cwd
  # then disambiguates between siblings.

  def test_cwd_tiering_selects_the_row_whose_cwd_contains_the_query_cwd
    Plastic::DB::Sessions.register(
      @conn, session_id: "shared--41", host: "h", pid: 1, cwd: "/repo/.claude/worktrees/41--demo",
      active_intent_id: "41", auto: true, now: t
    )
    Plastic::DB::Sessions.register(
      @conn, session_id: "shared--52", host: "h", pid: 2, cwd: "/repo/.claude/worktrees/52--other",
      active_intent_id: "52", auto: true, now: t(5)
    )

    row = Plastic::DB::Sessions.active_for(
      @conn, session: "shared", cwd: "/repo/.claude/worktrees/41--demo/scripts/lib"
    )
    assert_equal "shared--41", row["session_id"],
      "cwd inside one sibling's own worktree must select it over an off-cwd sibling"
  end

  def test_cwd_tiering_off_cwd_falls_back_to_auto_preference_then_newest
    Plastic::DB::Sessions.register(
      @conn, session_id: "shared--41", host: "h", pid: 1, cwd: "/repo/.claude/worktrees/41--demo",
      active_intent_id: "41", auto: false, now: t
    )
    Plastic::DB::Sessions.register(
      @conn, session_id: "shared--52", host: "h", pid: 2, cwd: "/repo/.claude/worktrees/52--other",
      active_intent_id: "52", auto: true, now: t(5)
    )

    # cwd overlaps neither sibling: fall back to auto-preference (52 is auto).
    row = Plastic::DB::Sessions.active_for(@conn, session: "shared", cwd: "/somewhere/else")
    assert_equal "shared--52", row["session_id"]
  end

  def test_cwd_tiering_newest_last_seen_at_when_no_auto_preference_breaks_tie
    Plastic::DB::Sessions.register(
      @conn, session_id: "shared--41", host: "h", pid: 1, cwd: "/repo/.claude/worktrees/41--demo",
      active_intent_id: "41", auto: false, now: t
    )
    Plastic::DB::Sessions.register(
      @conn, session_id: "shared--52", host: "h", pid: 2, cwd: "/repo/.claude/worktrees/52--other",
      active_intent_id: "52", auto: false, now: t(5)
    )

    row = Plastic::DB::Sessions.active_for(@conn, session: "shared", cwd: "/somewhere/else")
    assert_equal "shared--52", row["session_id"], "neither is auto-armed; newest last_seen_at wins"
  end

  def test_active_for_fails_open_on_nil_conn
    assert_nil Plastic::DB::Sessions.active_for(nil, session: "sess-1", cwd: "/tmp")
  end

  def test_active_for_returns_nil_when_no_rows_at_all
    assert_nil Plastic::DB::Sessions.active_for(@conn, session: nil, cwd: "/tmp")
  end

  # --- to_bridge_data: adapter parity (the migration spine) -------------------

  def setup_parity_fixture(auto:)
    home = Dir.mktmpdir("db-sessions-parity-home")
    store = File.join(home, ".plastic", "projects", "demo", "store")
    intent_dir = File.join(store, "77--demo")
    FileUtils.mkdir_p(intent_dir)
    File.write(File.join(intent_dir, "77--demo.md"), "## Intent\nDemo\n")

    index = File.join(File.dirname(store), "INDEX.md")
    File.write(index, "## Active\n- [77 — demo](77--demo/77--demo.md)\n\n## Future\n")

    { home: home, store: store, intent_dir: intent_dir }
  ensure
    # no-op; cleanup handled by caller via FileUtils.rm_rf(home)
  end

  def test_to_bridge_data_parity_with_code_gate_decision
    fx = setup_parity_fixture(auto: true)
    target = File.join(fx[:home], "code", "app.rb")
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, "puts 1\n")

    legacy = {
      "session" => "sess-1",
      "intent" => { "id" => "77", "store" => fx[:store], "dir" => "77--demo", "name" => "demo" },
      "build" => { "auto" => true },
    }

    Plastic::DB::Sessions.register(
      @conn, session_id: "sess-1", host: "h", pid: 1, cwd: fx[:intent_dir],
      active_intent_id: "77", auto: true, now: t
    )
    row = Plastic::DB::Sessions.active_for(@conn, session: "sess-1", cwd: fx[:intent_dir])
    adapted = Plastic::DB::Sessions.to_bridge_data(row, intent_dir: fx[:intent_dir], lock_row: nil)

    assert_equal fx[:store], adapted["intent"]["store"]
    assert_equal "77--demo", adapted["intent"]["dir"]
    assert_equal true, adapted["build"]["auto"]

    legacy_verdict = Bridge.code_gate_decision(legacy, target, home: fx[:home])
    adapted_verdict = Bridge.code_gate_decision(adapted, target, home: fx[:home])

    refute_nil legacy_verdict, "sanity: How not reached yet, auto armed, must block"
    assert_equal legacy_verdict, adapted_verdict,
      "the adapter's Hash must drive code_gate_decision to the identical verdict as a hand-built bridge"
  ensure
    FileUtils.rm_rf(fx[:home]) if fx
  end

  def test_to_bridge_data_parity_with_code_gate_decision_allows_once_how_reached
    fx = setup_parity_fixture(auto: true)
    File.write(File.join(fx[:intent_dir], "plan.md"), "plan\n")
    FileUtils.mkdir_p(File.join(fx[:intent_dir], "actions"))
    File.write(File.join(fx[:intent_dir], "checklist.md"), "checklist\n")
    target = File.join(fx[:home], "code", "app.rb")
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, "puts 1\n")

    legacy = {
      "session" => "sess-1",
      "intent" => { "id" => "77", "store" => fx[:store], "dir" => "77--demo", "name" => "demo" },
      "build" => { "auto" => true },
    }

    Plastic::DB::Sessions.register(
      @conn, session_id: "sess-1", host: "h", pid: 1, cwd: fx[:intent_dir],
      active_intent_id: "77", auto: true, now: t
    )
    row = Plastic::DB::Sessions.active_for(@conn, session: "sess-1", cwd: fx[:intent_dir])
    adapted = Plastic::DB::Sessions.to_bridge_data(row, intent_dir: fx[:intent_dir], lock_row: nil)

    legacy_verdict = Bridge.code_gate_decision(legacy, target, home: fx[:home])
    adapted_verdict = Bridge.code_gate_decision(adapted, target, home: fx[:home])

    assert_nil legacy_verdict, "sanity: plan.md + checklist.md present, How reached, must allow"
    assert_nil adapted_verdict
  ensure
    FileUtils.rm_rf(fx[:home]) if fx
  end

  def test_to_bridge_data_parity_with_lock_gate_decision_allow_and_deny
    fx = setup_parity_fixture(auto: false)
    file_in_intent = File.join(fx[:intent_dir], "plan.md")

    # lock_gate_decision resolves its OWN store connection from the file path
    # (fx's store), independent of this test's @conn (a different tmpdir).
    fx_conn = Plastic::DB.connect(File.dirname(fx[:store]))
    Plastic::DB::Leases.acquire(fx_conn, "77", session: "owner-session", host: "h")

    Plastic::DB::Sessions.register(
      @conn, session_id: "owner-session", host: "h", pid: 1, cwd: fx[:intent_dir],
      active_intent_id: "77", auto: false, now: t
    )
    row = Plastic::DB::Sessions.active_for(@conn, session: "owner-session", cwd: fx[:intent_dir])
    adapted = Plastic::DB::Sessions.to_bridge_data(row, intent_dir: fx[:intent_dir], lock_row: nil)

    legacy_owner = { "session" => "owner-session", "intent" => { "id" => "77" } }

    legacy_allow = Bridge.lock_gate_decision(legacy_owner, file_in_intent, session: "owner-session", home: fx[:home])
    adapted_allow = Bridge.lock_gate_decision(adapted, file_in_intent, session: "owner-session", home: fx[:home])
    assert_nil legacy_allow
    assert_nil adapted_allow

    legacy_deny = Bridge.lock_gate_decision(legacy_owner, file_in_intent, session: "someone-else", home: fx[:home])
    adapted_deny = Bridge.lock_gate_decision(adapted, file_in_intent, session: "someone-else", home: fx[:home])
    refute_nil legacy_deny, "sanity: a foreign session must be denied"
    assert_equal legacy_deny, adapted_deny,
      "the adapter's Hash must drive lock_gate_decision to the identical verdict as a hand-built bridge"
  ensure
    FileUtils.rm_rf(fx[:home]) if fx
  end

  # --- current_lock_row: thin read join to lock_leases -----------------------

  def test_current_lock_row_reads_the_live_delivery_grain_lease
    now = t.utc.iso8601
    @conn.execute(
      "INSERT INTO lock_leases (intent_id, artifact, owner_session, host, acquired_at, expires_at, released_at, created_at, updated_at) " \
      "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
      ["77", nil, "owner-session", "host-a", now, now, nil, now, now]
    )

    lock_row = Plastic::DB::Sessions.current_lock_row(@conn, "77")
    refute_nil lock_row
    assert_equal "owner-session", lock_row["owner_session"]
    assert_equal "host-a", lock_row["host"]
  end

  def test_current_lock_row_ignores_released_leases
    now = t.utc.iso8601
    @conn.execute(
      "INSERT INTO lock_leases (intent_id, artifact, owner_session, host, acquired_at, expires_at, released_at, created_at, updated_at) " \
      "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
      ["77", nil, "owner-session", "host-a", now, now, now, now, now]
    )

    assert_nil Plastic::DB::Sessions.current_lock_row(@conn, "77")
  end

  def test_current_lock_row_fails_open_on_nil_conn
    assert_nil Plastic::DB::Sessions.current_lock_row(nil, "77")
  end

  def test_to_bridge_data_builds_lock_cache_shape_from_lock_row
    row = Plastic::DB::Sessions.register(
      @conn, session_id: "sess-1", host: "h", pid: 1, cwd: "/tmp/a",
      active_intent_id: "41", auto: true, now: t
    )
    lock_row = { "owner_session" => "sess-1", "host" => "host-a", "acquired_at" => t.utc.iso8601, "artifact" => nil }

    adapted = Plastic::DB::Sessions.to_bridge_data(row, intent_dir: "/store/41--demo", lock_row: lock_row)

    assert_equal "sess-1", adapted["lock"]["owner_session"]
    assert_equal "host-a", adapted["lock"]["host"]
    assert_equal "delivery", adapted["lock"]["type"]
    assert_equal [], adapted["lock"]["delegates"]
  end

  def test_to_bridge_data_lock_cache_defaults_when_no_lock_row
    row = Plastic::DB::Sessions.register(
      @conn, session_id: "sess-1", host: "h", pid: 1, cwd: "/tmp/a",
      active_intent_id: "41", auto: true, now: t
    )
    adapted = Plastic::DB::Sessions.to_bridge_data(row, intent_dir: "/store/41--demo", lock_row: nil)

    assert_nil adapted["lock"]["owner_session"]
    assert_equal [], adapted["lock"]["delegates"]
  end

  def test_to_bridge_data_nil_row_returns_nil
    assert_nil Plastic::DB::Sessions.to_bridge_data(nil, intent_dir: "/store/41--demo", lock_row: nil)
  end
end
