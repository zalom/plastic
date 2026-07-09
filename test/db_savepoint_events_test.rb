require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "sqlite3"

require_relative "../scripts/lib/db"
require_relative "../scripts/lib/db/savepoint_events"
require_relative "../scripts/lib/bridge"

# Hermetic unit tests for Plastic::DB::SavepointEvents (intent 41, ACTION_5):
# the savepoint_events append-only ledger, milestone dedup, the JSONL export
# with its trailing operational-state record, and the rebuild-from-export
# durable-recovery path -- including the AC8 full-lifecycle export test.
# Dir.mktmpdir store + Dir.mktmpdir intent dir, injected occurred_at:, no
# Time.now anywhere.
#
# @intent_dir is nested at <store_home>/store/41--full-lifecycle (not a bare
# mktmpdir) so the AC8 test below can route its terminal Done stamp through
# the REAL production path, Bridge.append_terminal_savepoint, which resolves
# store_home/intent_id from the directory shape (Bridge.store_and_id_for).
class DbSavepointEventsTest < Minitest::Test
  def setup
    @store_home = Dir.mktmpdir("plastic-db-savepoint-store")
    @intent_dir = File.join(@store_home, "store", "41--full-lifecycle")
    FileUtils.mkdir_p(@intent_dir)
    @conn = Plastic::DB.connect(@store_home)
  end

  def teardown
    FileUtils.rm_rf(@store_home)
  end

  def seed_intent(intent_id, status: "active", quadrant: "quick_win", now: t(0))
    @conn.execute(
      "INSERT INTO intents (intent_id, status, quadrant, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
      [intent_id, status, quadrant, now, now]
    )
  end

  def seed_roadmap_entry(intent_id, slug:, batch_number:, now: t(0))
    @conn.execute("INSERT INTO roadmaps (slug, title, goal, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
                  [slug, slug, "goal", now, now])
    roadmap_id = @conn.execute("SELECT id FROM roadmaps WHERE slug = ?", [slug]).dig(0, 0)
    @conn.execute(
      "INSERT INTO roadmap_entries (roadmap_id, intent_id, batch_number, status, position, created_at, updated_at) " \
      "VALUES (?, ?, ?, ?, ?, ?, ?)",
      [roadmap_id, intent_id, batch_number, "queued", 1, now, now]
    )
  end

  def t(seconds)
    (Time.utc(2026, 7, 9) + seconds).strftime("%Y-%m-%dT%H:%M:%SZ")
  end

  # Same instant as t(seconds), as a Time (Bridge's now: wants an object that
  # responds to .utc.iso8601, not the pre-formatted String t() returns).
  def time_at(seconds)
    Time.utc(2026, 7, 9) + seconds
  end

  def jsonl_lines(path)
    File.readlines(path).reject { |l| l.strip.empty? }.map { |l| JSON.parse(l) }
  end

  # --- stamp -------------------------------------------------------------

  def test_stamp_appends_rows_in_order
    seed_intent("41")

    Plastic::DB::SavepointEvents.stamp(@conn, intent_id: "41", stage: "Exec", event_type: "note-a",
                                        actor_session: "s-1", occurred_at: t(0))
    Plastic::DB::SavepointEvents.stamp(@conn, intent_id: "41", stage: "Exec", event_type: "note-b",
                                        actor_session: "s-1", occurred_at: t(1))

    rows = @conn.execute("SELECT event_type FROM savepoint_events ORDER BY occurred_at ASC, id ASC")
    assert_equal [["note-a"], ["note-b"]], rows
  end

  def test_stamp_dedupes_milestone_events
    seed_intent("41")

    first = Plastic::DB::SavepointEvents.stamp(@conn, intent_id: "41", stage: "Why", event_type: "spec.md created",
                                                actor_session: "s-1", occurred_at: t(0))
    second = Plastic::DB::SavepointEvents.stamp(@conn, intent_id: "41", stage: "Why", event_type: "spec.md created",
                                                 actor_session: "s-2", occurred_at: t(1))

    assert first
    refute second
    rows = @conn.execute("SELECT actor_session FROM savepoint_events WHERE stage = 'Why' AND event_type = 'spec.md created'")
    assert_equal [["s-1"]], rows
  end

  def test_stamp_does_not_dedupe_free_form_events
    seed_intent("41")

    Plastic::DB::SavepointEvents.stamp(@conn, intent_id: "41", stage: "Exec", event_type: "progress-note",
                                        actor_session: "s-1", occurred_at: t(0))
    Plastic::DB::SavepointEvents.stamp(@conn, intent_id: "41", stage: "Exec", event_type: "progress-note",
                                        actor_session: "s-1", occurred_at: t(1))

    rows = @conn.execute("SELECT COUNT(*) FROM savepoint_events WHERE event_type = 'progress-note'")
    assert_equal 2, rows.first.first
  end

  def test_stamp_stores_payload_as_json_text
    seed_intent("41")

    Plastic::DB::SavepointEvents.stamp(@conn, intent_id: "41", stage: "Exec", event_type: "progress-note",
                                        actor_session: "s-1", occurred_at: t(0), payload: { "note" => "did the thing" })

    payload = @conn.execute("SELECT payload FROM savepoint_events WHERE event_type = 'progress-note'").first.first
    assert_equal({ "note" => "did the thing" }, JSON.parse(payload))
  end

  def test_stamp_fails_open_on_nil_conn
    assert_nil Plastic::DB::SavepointEvents.stamp(nil, intent_id: "41", stage: "Exec", event_type: "x",
                                                   actor_session: "s-1", occurred_at: t(0))
  end

  def test_stamp_fails_open_when_intents_row_missing
    result = Plastic::DB::SavepointEvents.stamp(@conn, intent_id: "does-not-exist", stage: "Exec", event_type: "x",
                                                 actor_session: "s-1", occurred_at: t(0))
    refute result
    assert_equal 0, @conn.execute("SELECT COUNT(*) FROM savepoint_events").first.first
  end

  # --- export --------------------------------------------------------------

  def test_export_writes_valid_jsonl_with_event_and_state_lines
    seed_intent("41", status: "active", quadrant: "quick_win")
    seed_roadmap_entry("41", slug: "launch-batch", batch_number: 2)
    Plastic::DB::SavepointEvents.stamp(@conn, intent_id: "41", stage: "Why", event_type: "spec.md created",
                                        actor_session: "s-1", occurred_at: t(0))
    Plastic::DB::SavepointEvents.stamp(@conn, intent_id: "41", stage: "How", event_type: "plan.md created",
                                        actor_session: "s-1", occurred_at: t(1))

    path = Plastic::DB::SavepointEvents.export(@conn, intent_id: "41", intent_dir: @intent_dir)

    assert_equal File.join(@intent_dir, "savepoint.jsonl"), path
    lines = jsonl_lines(path)
    assert_equal 3, lines.length

    events = lines[0..1]
    assert_equal %w[event event], events.map { |l| l["kind"] }
    assert_equal ["spec.md created", "plan.md created"], events.map { |l| l["event_type"] }
    assert_equal [t(0), t(1)], events.map { |l| l["occurred_at"] }

    state = lines.last
    assert_equal(
      { "kind" => "state", "status" => "active", "quadrant" => "quick_win", "queue" => "launch-batch", "batch" => 2 },
      state
    )
  end

  def test_export_orders_by_occurred_at_then_id_regardless_of_insertion_order
    seed_intent("41")
    Plastic::DB::SavepointEvents.stamp(@conn, intent_id: "41", stage: "Exec", event_type: "b",
                                        actor_session: "s-1", occurred_at: t(5))
    Plastic::DB::SavepointEvents.stamp(@conn, intent_id: "41", stage: "Exec", event_type: "a",
                                        actor_session: "s-1", occurred_at: t(1))

    path = Plastic::DB::SavepointEvents.export(@conn, intent_id: "41", intent_dir: @intent_dir)
    events = jsonl_lines(path).select { |l| l["kind"] == "event" }

    assert_equal %w[a b], events.map { |l| l["event_type"] }
  end

  def test_export_state_line_has_nil_queue_and_batch_when_not_on_a_roadmap
    seed_intent("41", status: "done", quadrant: "next_big")

    path = Plastic::DB::SavepointEvents.export(@conn, intent_id: "41", intent_dir: @intent_dir)
    state = jsonl_lines(path).last

    assert_equal({ "kind" => "state", "status" => "done", "quadrant" => "next_big", "queue" => nil, "batch" => nil },
                 state)
  end

  def test_export_fails_open_on_nil_conn
    assert_nil Plastic::DB::SavepointEvents.export(nil, intent_id: "41", intent_dir: @intent_dir)
    refute File.exist?(File.join(@intent_dir, "savepoint.jsonl"))
  end

  def test_export_fails_open_when_intents_row_missing
    assert_nil Plastic::DB::SavepointEvents.export(@conn, intent_id: "does-not-exist", intent_dir: @intent_dir)
    refute File.exist?(File.join(@intent_dir, "savepoint.jsonl"))
  end

  # --- rebuild_from_export ---------------------------------------------------

  def test_rebuild_from_export_fails_open_on_nil_conn
    assert_nil Plastic::DB::SavepointEvents.rebuild_from_export(nil, intent_id: "41", intent_dir: @intent_dir)
  end

  def test_rebuild_from_export_fails_open_when_file_missing
    seed_intent("41")
    assert_nil Plastic::DB::SavepointEvents.rebuild_from_export(@conn, intent_id: "41", intent_dir: @intent_dir)
  end

  # --- AC8: full-lifecycle export + rebuild round-trip ----------------------

  def test_full_lifecycle_export_grows_monotonically_and_rebuild_round_trips
    seed_intent("41", status: "active", quadrant: "quick_win")
    seed_roadmap_entry("41", slug: "launch-batch", batch_number: 1)

    sizes = []

    # What: the intent file itself lands (mirrors bridge.rb's What milestone).
    Plastic::DB::SavepointEvents.stamp(@conn, intent_id: "41", stage: "What", event_type: "41--add-plastic-database-layer.md",
                                        actor_session: "s-1", occurred_at: t(0))

    # Why: spec.md lands -- a gate, export fires.
    Plastic::DB::SavepointEvents.stamp(@conn, intent_id: "41", stage: "Why", event_type: "spec.md created",
                                        actor_session: "s-1", occurred_at: t(1))
    sizes << File.size(Plastic::DB::SavepointEvents.export(@conn, intent_id: "41", intent_dir: @intent_dir))

    # How: plan.md then checklist.md land -- two gates, two exports.
    Plastic::DB::SavepointEvents.stamp(@conn, intent_id: "41", stage: "How", event_type: "plan.md created",
                                        actor_session: "s-1", occurred_at: t(2))
    sizes << File.size(Plastic::DB::SavepointEvents.export(@conn, intent_id: "41", intent_dir: @intent_dir))

    Plastic::DB::SavepointEvents.stamp(@conn, intent_id: "41", stage: "How", event_type: "checklist.md created",
                                        actor_session: "s-1", occurred_at: t(3))
    sizes << File.size(Plastic::DB::SavepointEvents.export(@conn, intent_id: "41", intent_dir: @intent_dir))

    # Exec: outcome.md lands -- a gate, export fires.
    Plastic::DB::SavepointEvents.stamp(@conn, intent_id: "41", stage: "Exec", event_type: "outcome.md created",
                                        actor_session: "s-1", occurred_at: t(4))
    sizes << File.size(Plastic::DB::SavepointEvents.export(@conn, intent_id: "41", intent_dir: @intent_dir))

    # Done: terminal disposition. Flip the mirror's authoritative status/quadrant
    # too, exactly as the real completion path would, before the final export.
    # This step goes through the PRODUCTION stamp path, Bridge.append_terminal_savepoint,
    # instead of a hand call to SavepointEvents.stamp + SavepointEvents.export: the
    # BLOCKER this test guards against was the Done gate export only firing from a
    # hook's file-landing check, never from the stamp itself, so proving the export
    # happens automatically here (no explicit .export call) is the point.
    @conn.execute("UPDATE intents SET status = 'done', quadrant = NULL WHERE intent_id = '41'")
    assert Bridge.append_terminal_savepoint(@intent_dir, "delivered", session: "s-1", now: time_at(5))
    final_path = File.join(@intent_dir, "savepoint.jsonl")
    sizes << File.size(final_path)

    assert_equal sizes.sort, sizes, "savepoint.jsonl must grow monotonically at every gate"

    final_lines_before = jsonl_lines(final_path)
    assert_equal 6, final_lines_before.count { |l| l["kind"] == "event" }
    final_state = final_lines_before.last
    assert_equal "done", final_state["status"]
    assert_nil final_state["quadrant"]
    assert_equal "launch-batch", final_state["queue"]
    assert_equal 1, final_state["batch"]

    original_jsonl_bytes = File.read(final_path)

    # Wipe the DB (all rows, keep the empty schema) and rebuild from the
    # committed JSONL alone. Children before parents: savepoint_events
    # references intents, roadmap_entries references roadmaps.
    %w[savepoint_events roadmap_entries intents roadmaps].each { |table| @conn.execute("DELETE FROM #{table}") }
    assert_equal 0, @conn.execute("SELECT COUNT(*) FROM savepoint_events").first.first
    assert_equal 0, @conn.execute("SELECT COUNT(*) FROM intents").first.first

    result = Plastic::DB::SavepointEvents.rebuild_from_export(@conn, intent_id: "41", intent_dir: @intent_dir)
    assert result

    rebuilt_events = @conn.execute("SELECT stage, event_type, actor_session, payload, occurred_at " \
                                    "FROM savepoint_events se JOIN intents i ON se.intent_id = i.id " \
                                    "WHERE i.intent_id = '41' ORDER BY occurred_at ASC, se.id ASC")
    assert_equal 6, rebuilt_events.length
    assert_equal %w[What Why How How Exec Done], rebuilt_events.map { |r| r[0] }

    rebuilt_intent = @conn.execute("SELECT status, quadrant FROM intents WHERE intent_id = '41'").first
    assert_equal ["done", nil], rebuilt_intent

    rebuilt_roadmap_entry = @conn.execute(
      "SELECT roadmaps.slug, roadmap_entries.batch_number FROM roadmap_entries " \
      "JOIN roadmaps ON roadmap_entries.roadmap_id = roadmaps.id WHERE roadmap_entries.intent_id = '41'"
    ).first
    assert_equal ["launch-batch", 1], rebuilt_roadmap_entry

    reexported_path = Plastic::DB::SavepointEvents.export(@conn, intent_id: "41", intent_dir: @intent_dir)
    assert_equal original_jsonl_bytes, File.read(reexported_path),
                 "re-export after rebuild must be byte-identical to the pre-wipe export"
  end
end
