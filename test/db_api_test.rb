require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "time"

require_relative "../scripts/lib/db"

# Hermetic unit tests for the Plastic::DB query + record verb API (intent 41,
# ACTION_7, AC5): every verb is exercised through the FACADE ONLY (never raw
# SQL, never a lower-level module directly) so the test itself proves D7's
# "no consumer touches SQL" holds for its own setup and assertions, not just
# for production code. Dir.mktmpdir store, injected now:/occurred_at:, no
# Time.now anywhere.
class DbApiTest < Minitest::Test
  def setup
    @store_home = Dir.mktmpdir("plastic-db-api-store")
  end

  def teardown
    FileUtils.rm_rf(@store_home)
  end

  def t(seconds)
    Time.utc(2026, 7, 9) + seconds
  end

  def iso(time)
    time.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
  end

  # --- query verbs -----------------------------------------------------------

  def test_by_status_returns_the_right_set_for_each_status
    Plastic::DB.set_status(@store_home, "1", "active", now: t(0))
    Plastic::DB.set_status(@store_home, "2", "done", now: t(0))
    Plastic::DB.set_status(@store_home, "3", "abandoned", now: t(0))
    Plastic::DB.set_status(@store_home, "4", "deferred", now: t(0))

    assert_equal ["1"], Plastic::DB.by_status(@store_home, "active").map { |h| h["intent_id"] }
    assert_equal ["2"], Plastic::DB.by_status(@store_home, "done").map { |h| h["intent_id"] }
    assert_equal ["3"], Plastic::DB.by_status(@store_home, "abandoned").map { |h| h["intent_id"] }
    assert_equal ["4"], Plastic::DB.by_status(@store_home, "deferred").map { |h| h["intent_id"] }
  end

  def test_by_quadrant_filters_by_quadrant_only
    Plastic::DB.set_status(@store_home, "1", "active", now: t(0))
    Plastic::DB.set_quadrant(@store_home, "1", "quick_win", now: t(0))
    Plastic::DB.set_status(@store_home, "2", "active", now: t(0))
    Plastic::DB.set_quadrant(@store_home, "2", "next_big", now: t(0))

    assert_equal ["1"], Plastic::DB.by_quadrant(@store_home, "quick_win").map { |h| h["intent_id"] }
    assert_equal ["2"], Plastic::DB.by_quadrant(@store_home, "next_big").map { |h| h["intent_id"] }
  end

  def test_by_queue_with_and_without_batch
    Plastic::DB.set_status(@store_home, "1", "active", now: t(0))
    Plastic::DB.set_status(@store_home, "2", "active", now: t(0))
    Plastic::DB.roadmap_upsert(@store_home, slug: "launch", title: "Launch", goal: "Ship it", now: t(0))
    Plastic::DB.roadmap_entry_set(@store_home, roadmap_slug: "launch", intent_id: "1", batch_number: 1, position: 1, now: t(0))
    Plastic::DB.roadmap_entry_set(@store_home, roadmap_slug: "launch", intent_id: "2", batch_number: 2, position: 1, now: t(0))

    assert_equal %w[1 2], Plastic::DB.by_queue(@store_home, "launch").map { |h| h["intent_id"] }
    assert_equal ["1"], Plastic::DB.by_queue(@store_home, "launch", batch: 1).map { |h| h["intent_id"] }
    assert_equal ["2"], Plastic::DB.by_queue(@store_home, "launch", batch: 2).map { |h| h["intent_id"] }
  end

  def test_by_queue_returns_empty_for_unknown_roadmap
    assert_equal [], Plastic::DB.by_queue(@store_home, "no-such-roadmap")
  end

  # --- record verbs mutate the right row and are visible on re-query --------

  def test_set_status_mutates_and_is_visible_on_requery
    Plastic::DB.set_status(@store_home, "1", "active", now: t(0))
    assert_equal ["1"], Plastic::DB.by_status(@store_home, "active").map { |h| h["intent_id"] }

    Plastic::DB.set_status(@store_home, "1", "done", now: t(1))
    assert_empty Plastic::DB.by_status(@store_home, "active")
    assert_equal ["1"], Plastic::DB.by_status(@store_home, "done").map { |h| h["intent_id"] }
  end

  def test_set_quadrant_mutates_independently_of_status
    Plastic::DB.set_status(@store_home, "1", "active", now: t(0))
    Plastic::DB.set_quadrant(@store_home, "1", "quick_win", now: t(0))
    Plastic::DB.set_quadrant(@store_home, "1", "next_big", now: t(1))

    row = Plastic::DB.by_status(@store_home, "active").first
    assert_equal "next_big", row["quadrant"]
    assert_equal "active", row["status"], "set_quadrant must never touch status"
  end

  def test_stamp_event_writes_a_savepoint_events_row_visible_via_export
    Plastic::DB.set_status(@store_home, "1", "active", now: t(0))
    result = Plastic::DB.stamp_event(@store_home, "1", stage: "Exec", event_type: "progress-note",
                                      actor_session: "s-1", payload: { "note" => "did it" }, occurred_at: iso(t(0)))
    assert result

    intent_dir = Dir.mktmpdir("plastic-db-api-intent")
    begin
      path = Plastic::DB.export_savepoint(@store_home, "1", intent_dir: intent_dir)
      lines = File.readlines(path).map { |l| JSON.parse(l) }
      event = lines.find { |l| l["kind"] == "event" }
      assert_equal "progress-note", event["event_type"]
      assert_equal({ "note" => "did it" }, event["payload"])
    ensure
      FileUtils.rm_rf(intent_dir)
    end
  end

  def test_lease_acquire_renew_release_round_trip
    status, row = Plastic::DB.lease_acquire(@store_home, "1", session: "s-a", host: "h-a", now: t(0))
    assert_equal :acquired, status
    assert_equal "s-a", row["owner_session"]

    renew_status = Plastic::DB.lease_renew(@store_home, "1", session: "s-a", now: t(0), renew_window: 10_000)
    assert_equal :renewed, renew_status

    release_status = Plastic::DB.lease_release(@store_home, "1", session: "s-a", now: t(0))
    assert_equal :released, release_status

    status2, row2 = Plastic::DB.lease_acquire(@store_home, "1", session: "s-b", host: "h-b", now: t(1))
    assert_equal :acquired, status2, "a released lease must be free for a new owner"
    assert_equal "s-b", row2["owner_session"]
  end

  def test_lease_acquire_respects_artifact_grain
    Plastic::DB.lease_acquire(@store_home, "1", artifact: "outcome.md", session: "s-a", host: "h-a", now: t(0))
    status, row = Plastic::DB.lease_acquire(@store_home, "1", artifact: "outcome.md", session: "s-b", host: "h-b", now: t(1))

    assert_equal :held, status
    assert_equal "s-a", row["owner_session"]
  end

  def test_session_register_update_end_round_trip
    row = Plastic::DB.session_register(@store_home, session_id: "sess-1", host: "h", pid: 1, cwd: "/tmp",
                                        active_intent_id: "1", auto: true, now: t(0))
    assert_equal "sess-1", row["session_id"]
    assert_equal "1", row["active_intent_id"]

    updated = Plastic::DB.session_update(@store_home, session_id: "sess-1", cwd: "/tmp2", now: t(1))
    assert_equal "/tmp2", updated["cwd"]

    ended = Plastic::DB.session_end(@store_home, session_id: "sess-1")
    assert_equal "sess-1", ended
    assert_nil Plastic::DB.session_update(@store_home, session_id: "sess-1", cwd: "/tmp3", now: t(2)),
               "an ended session has no row left to update"
  end

  def test_roadmap_upsert_and_entry_set_round_trip
    Plastic::DB.set_status(@store_home, "1", "active", now: t(0))
    row = Plastic::DB.roadmap_upsert(@store_home, slug: "launch", title: "Launch", goal: "Ship", now: t(0))
    assert_equal "launch", row["slug"]
    assert_equal "Launch", row["title"]

    entry = Plastic::DB.roadmap_entry_set(@store_home, roadmap_slug: "launch", intent_id: "1", batch_number: 3, now: t(0))
    assert_equal 3, entry["batch_number"]

    updated_entry = Plastic::DB.roadmap_entry_set(@store_home, roadmap_slug: "launch", intent_id: "1", batch_number: 7, now: t(1))
    assert_equal 7, updated_entry["batch_number"]
    assert_equal ["1"], Plastic::DB.by_queue(@store_home, "launch", batch: 7).map { |h| h["intent_id"] }
  end

  def test_roadmap_upsert_is_idempotent_on_slug
    Plastic::DB.roadmap_upsert(@store_home, slug: "launch", title: "Launch", goal: "Ship", now: t(0))
    row = Plastic::DB.roadmap_upsert(@store_home, slug: "launch", title: "Launch v2", goal: "Ship faster", now: t(1))

    assert_equal "Launch v2", row["title"]
    assert_equal "Ship faster", row["goal"]
  end

  # --- fail-open: sqlite3 forced absent --------------------------------------

  def test_query_verbs_fail_open_when_sqlite3_unavailable
    assert_equal [], Plastic::DB.by_status(@store_home, "active", available: false)
    assert_equal [], Plastic::DB.by_quadrant(@store_home, "quick_win", available: false)
    assert_equal [], Plastic::DB.by_queue(@store_home, "launch", available: false)
  end

  def test_record_verbs_fail_open_when_sqlite3_unavailable
    assert_nil Plastic::DB.set_status(@store_home, "1", "active", available: false)
    assert_nil Plastic::DB.set_quadrant(@store_home, "1", "quick_win", available: false)
    assert_nil Plastic::DB.stamp_event(@store_home, "1", stage: "Exec", event_type: "x", actor_session: "s",
                                        occurred_at: iso(t(0)), available: false)
    assert_equal [:fail_open, nil],
                 Plastic::DB.lease_acquire(@store_home, "1", session: "s", host: "h", available: false)
    assert_equal :fail_open, Plastic::DB.lease_renew(@store_home, "1", session: "s", available: false)
    assert_equal :fail_open, Plastic::DB.lease_release(@store_home, "1", session: "s", available: false)
    assert_nil Plastic::DB.session_register(@store_home, session_id: "s", host: "h", pid: 1, cwd: "/tmp",
                                             active_intent_id: nil, auto: false, available: false)
    assert_nil Plastic::DB.session_update(@store_home, session_id: "s", cwd: "/tmp2", available: false)
    assert_nil Plastic::DB.session_end(@store_home, session_id: "s", available: false)
    assert_nil Plastic::DB.roadmap_upsert(@store_home, slug: "launch", title: "L", goal: "G", available: false)
    assert_nil Plastic::DB.roadmap_entry_set(@store_home, roadmap_slug: "launch", intent_id: "1", available: false)
    assert_nil Plastic::DB.export_savepoint(@store_home, "1", intent_dir: @store_home, available: false)
  end

  def test_no_sql_in_consumer_every_verb_used_above_is_a_plastic_db_facade_call
    # Structural guard: every call in this file is `Plastic::DB.<verb>`. This
    # test documents the constraint by re-running a tiny round trip and
    # asserting on the facade's own return shape, never on `conn.execute`.
    Plastic::DB.set_status(@store_home, "9", "active", now: t(0))
    result = Plastic::DB.by_status(@store_home, "active")
    assert_kind_of Array, result
    assert_kind_of Hash, result.first
  end
end
