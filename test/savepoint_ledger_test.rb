require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "time"
require_relative "../scripts/lib/bridge"
require_relative "../scripts/lib/db"

# Tests for the cycle-step savepoint ledger (intent 34), cut over to
# `savepoint_events` (DB, authoritative) plus the git-committed
# `savepoint.jsonl` export in intent 41's ACTION_11. Per-intent savepoint.md
# retires from the live flow: every append_* helper now stamps a DB row
# instead of formatting a text line, so this file asserts against
# Plastic::DB::SavepointEvents rows (via Bridge.savepoint_recorded_pairs and
# direct reads) rather than parsing savepoint.md content.
class SavepointLedgerTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("savepoint-ledger-home")
    @store = File.join(@home, "store")
    @dir = File.join(@store, "34--demo")
    FileUtils.mkdir_p(@dir)
    @intent_basename = "34--demo.md"
    write("34--demo.md", "## Intent\nDemo\n")
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def write(name, body = "x\n")
    path = File.join(@dir, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
    path
  end

  def conn
    Plastic::DB.connect(@home)
  end

  def events
    Plastic::DB::SavepointEvents.events_for(conn, "34")
  end

  def pairs
    events.map { |e| [e["stage"], e["event_type"]] }
  end

  # --- Task 1: savepoint_milestone (pure, unchanged) --------------------------

  def test_milestone_map_for_each_stage_file
    assert_equal ["What", @intent_basename], Bridge.savepoint_milestone(@dir, @intent_basename)
    assert_equal ["Why", "spec.md created"], Bridge.savepoint_milestone(@dir, "spec.md")
    assert_equal ["How", "plan.md created"], Bridge.savepoint_milestone(@dir, "plan.md")
    assert_equal ["How", "checklist.md created"], Bridge.savepoint_milestone(@dir, "checklist.md")
    assert_equal ["Exec", "outcome.md created"], Bridge.savepoint_milestone(@dir, "outcome.md")
  end

  def test_milestone_map_returns_nil_for_non_milestones
    assert_nil Bridge.savepoint_milestone(@dir, "ACTION_1.md")
    assert_nil Bridge.savepoint_milestone(@dir, "notes.md")
  end

  # --- Task 2: append_savepoint stamps a savepoint_events row -----------------

  def test_append_creates_a_stamped_event
    write("spec.md", "# Spec\nreal\n")
    t = Time.utc(2026, 6, 16, 14, 20, 0)
    assert_equal true, Bridge.append_savepoint(@dir, File.join(@dir, "spec.md"), now: t)
    assert_equal [["Why", "spec.md created"]], pairs
    row = events.first
    assert_equal t.utc.iso8601, row["occurred_at"]
  end

  def test_append_is_idempotent_per_milestone
    write("spec.md", "# Spec\nreal\n")
    t1 = Time.utc(2026, 6, 16, 14, 20, 0)
    t2 = Time.utc(2026, 6, 16, 15, 0, 0)
    assert_equal true, Bridge.append_savepoint(@dir, File.join(@dir, "spec.md"), now: t1)
    assert_equal false, Bridge.append_savepoint(@dir, File.join(@dir, "spec.md"), now: t2)
    assert_equal 1, events.length
  end

  def test_append_skips_sentinel_placeholder_lifecycle_file
    write("spec.md", "<!-- plastic:placeholder -->\n\nplaceholder\n")
    assert_equal false, Bridge.append_savepoint(@dir, File.join(@dir, "spec.md"), now: Time.now)
    assert_empty events
  end

  def test_append_ignores_non_milestone_files
    write("actions/ACTION_1.md")
    assert_equal false, Bridge.append_savepoint(@dir, File.join(@dir, "actions/ACTION_1.md"), now: Time.now)
    assert_empty events
  end

  def test_full_sequence_recorded_in_occurred_at_order
    seq = [
      [@intent_basename, Time.utc(2026, 6, 16, 14, 0, 0)],
      ["spec.md", Time.utc(2026, 6, 16, 14, 20, 0)],
      ["plan.md", Time.utc(2026, 6, 16, 15, 10, 0)],
      ["checklist.md", Time.utc(2026, 6, 16, 15, 11, 0)],
      ["outcome.md", Time.utc(2026, 6, 16, 16, 40, 0)],
    ]
    seq.each do |name, t|
      write(name, "real #{name}\n") unless name == @intent_basename
      Bridge.append_savepoint(@dir, File.join(@dir, name), now: t)
    end
    assert_equal [
      ["What", @intent_basename],
      ["Why", "spec.md created"],
      ["How", "plan.md created"],
      ["How", "checklist.md created"],
      ["Exec", "outcome.md created"],
    ], pairs
  end

  # --- Task 3: rebuild_savepoint reconstructs the DB from the JSONL export ---

  def test_rebuild_restores_events_from_the_committed_export
    write("spec.md")
    write("plan.md")
    write("checklist.md")
    FileUtils.mkdir_p(File.join(@dir, "actions"))
    Bridge.append_savepoint(@dir, File.join(@dir, @intent_basename))
    Bridge.append_savepoint(@dir, File.join(@dir, "spec.md"))
    Bridge.append_savepoint(@dir, File.join(@dir, "plan.md"))
    Bridge.append_savepoint(@dir, File.join(@dir, "checklist.md"))

    store_home_id = "34"
    Plastic::DB.export_savepoint(@home, store_home_id, intent_dir: @dir)
    assert File.exist?(File.join(@dir, "savepoint.jsonl"))

    # Wipe the DB row-level state and rebuild purely from the committed export.
    conn.execute("DELETE FROM savepoint_events")
    assert_empty events

    assert_equal true, Bridge.rebuild_savepoint(@dir)
    milestones = pairs.map(&:last)
    assert_equal [@intent_basename, "spec.md created", "plan.md created", "checklist.md created"], milestones
  end

  def test_rebuild_false_when_no_export_exists
    refute File.exist?(File.join(@dir, "savepoint.jsonl"))
    assert_equal false, Bridge.rebuild_savepoint(@dir)
  end

  # === Intent 81: state-from-ledger extensions ===============================

  # --- Pair-based idempotency -------------------------------------------------

  def test_recorded_pairs_parses_stage_and_event_type
    write("spec.md", "real\n")
    Bridge.append_savepoint(@dir, File.join(@dir, "spec.md"), now: Time.utc(2026, 6, 16))
    assert_equal [["Why", "spec.md created"]], Bridge.savepoint_recorded_pairs(@dir)
  end

  def test_started_events_for_distinct_stages_coexist
    # Both events share the literal event_type "started"; pair dedup must keep both.
    t = Time.utc(2026, 6, 16, 10, 0, 0)
    assert_equal true, Bridge.append_started_savepoint(@dir, File.join(@dir, "spec.md"), now: t)
    assert_equal true, Bridge.append_started_savepoint(@dir, File.join(@dir, "plan.md"), now: t + 60)
    assert_equal [["Why", "started"], ["How", "started"]], pairs
  end

  # --- started milestones -----------------------------------------------------

  def test_started_milestone_map
    assert_equal ["Why", "started"], Bridge.savepoint_started_milestone("spec.md")
    assert_equal ["How", "started"], Bridge.savepoint_started_milestone("plan.md")
    assert_nil Bridge.savepoint_started_milestone("checklist.md")
    assert_nil Bridge.savepoint_started_milestone("outcome.md")
    assert_nil Bridge.savepoint_started_milestone(@intent_basename)
  end

  def test_append_started_writes_before_artifact_exists
    # No real spec.md yet (the pre-write moment).
    t = Time.utc(2026, 6, 16, 11, 40, 0)
    assert_equal true, Bridge.append_started_savepoint(@dir, File.join(@dir, "spec.md"), now: t)
    assert_equal [["Why", "started"]], pairs
    assert_equal t.utc.iso8601, events.first["occurred_at"]
  end

  def test_append_started_noop_once_artifact_is_real
    write("spec.md", "real spec\n")
    assert_equal false, Bridge.append_started_savepoint(@dir, File.join(@dir, "spec.md"), now: Time.now)
    assert_empty events
  end

  def test_append_started_fires_for_placeholder_artifact
    # A sentinel placeholder is NOT a real stage file, so the stage is starting.
    write("plan.md", "#{Bridge::PLACEHOLDER_SENTINEL}\n\nplaceholder\n")
    assert_equal true, Bridge.append_started_savepoint(@dir, File.join(@dir, "plan.md"), now: Time.now)
    assert_equal [["How", "started"]], pairs
  end

  def test_append_started_idempotent
    t = Time.utc(2026, 6, 16, 11, 40, 0)
    assert_equal true, Bridge.append_started_savepoint(@dir, File.join(@dir, "spec.md"), now: t)
    assert_equal false, Bridge.append_started_savepoint(@dir, File.join(@dir, "spec.md"), now: t + 100)
    assert_equal 1, events.length
  end

  def test_append_started_nil_for_non_started_file
    assert_equal false, Bridge.append_started_savepoint(@dir, File.join(@dir, "outcome.md"), now: Time.now)
    assert_empty events
  end

  # --- Exec started companion -------------------------------------------------

  def test_append_exec_started
    t = Time.utc(2026, 6, 16, 12, 21, 0)
    assert_equal true, Bridge.append_exec_started(@dir, now: t)
    assert_equal [["Exec", "started"]], pairs
  end

  def test_append_exec_started_idempotent
    assert_equal true, Bridge.append_exec_started(@dir, now: Time.now)
    assert_equal false, Bridge.append_exec_started(@dir, now: Time.now)
    assert_equal 1, events.length
  end

  # --- terminal event ----------------------------------------------------------

  def test_append_terminal_delivered
    t = Time.utc(2026, 6, 16, 16, 45, 0)
    assert_equal true, Bridge.append_terminal_savepoint(@dir, "delivered", now: t)
    assert_equal [["Done", "delivered"]], pairs
  end

  def test_append_terminal_abandoned
    assert_equal true, Bridge.append_terminal_savepoint(@dir, "abandoned", now: Time.now)
    assert_equal [["Done", "abandoned"]], pairs
  end

  def test_append_terminal_rejects_bad_disposition
    assert_raises(ArgumentError) { Bridge.append_terminal_savepoint(@dir, "done", now: Time.now) }
    assert_empty events
  end

  def test_append_terminal_idempotent_per_disposition
    assert_equal true, Bridge.append_terminal_savepoint(@dir, "delivered", now: Time.now)
    assert_equal false, Bridge.append_terminal_savepoint(@dir, "delivered", now: Time.now)
    assert_equal 1, events.length
  end

  # --- fail-open: no resolvable intent_id / DB unavailable --------------------

  def test_append_savepoint_false_outside_any_store
    loose = Dir.mktmpdir("loose-dir")
    write_path = File.join(loose, "spec.md")
    File.write(write_path, "spec\n")
    assert_equal false, Bridge.append_savepoint(loose, write_path)
  ensure
    FileUtils.rm_rf(loose)
  end

  # === Intent 130, D-A: Tier convenience line (unchanged, reads spec.md) =====

  def test_savepoint_tier_reads_top_line
    write("spec.md", "Tier: M\n\n# Spec: demo\n")
    assert_equal "M", Bridge.savepoint_tier(@dir)
  end

  def test_savepoint_tier_nil_when_absent
    write("spec.md", "# Spec: demo\n\nNo tier line here.\n")
    assert_nil Bridge.savepoint_tier(@dir)
  end

  def test_savepoint_tier_nil_when_spec_missing
    assert_nil Bridge.savepoint_tier(@dir)
  end

  def test_savepoint_tier_nil_when_malformed
    write("spec.md", "Tier: XL\n\n# Spec: demo\n")
    assert_nil Bridge.savepoint_tier(@dir)
  end
end
