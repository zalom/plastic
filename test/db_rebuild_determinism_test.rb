require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "time"
require "json"
require "sqlite3"

require_relative "../scripts/lib/db"
require_relative "../scripts/lib/db/rebuild"

# Hermetic tests for Plastic::DB::Rebuild (intent 41, ACTION_8): a full cold
# rebuild of every derived table from files-on-disk plus each intent's
# committed savepoint.jsonl snapshot, proven deterministic (AC3) via a
# canonical-logical-dump comparison across two INDEPENDENT rebuilds of the
# same fixture store (two separate tmpdir copies, two separate plastic.db
# files -- never the same conn twice). Intent ids stay single-digit on
# purpose, sidestepping any ambiguity in Mirror's existing (string, not
# numeric) directory sort, which this action reuses rather than refactors.
class DbRebuildDeterminismTest < Minitest::Test
  def teardown
    FileUtils.rm_rf(@store_a) if @store_a
    FileUtils.rm_rf(@store_b) if @store_b
  end

  # Writes one fixture store tree (intent files + committed savepoint.jsonl
  # snapshots) into a fresh Dir.mktmpdir and returns its store_home path.
  def build_fixture_store
    home = Dir.mktmpdir("plastic-db-rebuild-store")

    write_intent(home, id: "1", slug: "alpha", created: "2026-01-01", chain: ["2"], sources: [])
    write_intent(home, id: "2", slug: "beta", created: "2026-01-02", chain: [], sources: ["1"])
    write_intent(home, id: "3", slug: "gamma", created: nil, chain: [], sources: []) # no created: at all

    write_snapshot(home, "1",
                    events: [
                      { stage: "Why", event_type: "spec.md created", actor_session: "s-1", occurred_at: "2026-01-01T00:00:00Z" },
                      { stage: "How", event_type: "plan.md created", actor_session: "s-1", occurred_at: "2026-01-01T00:01:00Z" },
                    ],
                    state: { status: "active", quadrant: "quick_win", queue: "launch-batch", batch: 2 })

    write_snapshot(home, "2",
                    events: [
                      { stage: "Why", event_type: "spec.md created", actor_session: "s-1", occurred_at: "2026-01-02T00:00:00Z" },
                    ],
                    state: { status: "done", quadrant: nil, queue: nil, batch: nil })

    # intent "3" gets no savepoint.jsonl at all: its row must still rebuild
    # (from Mirror alone) with content-derived timestamps, no crash.

    home
  end

  def write_intent(home, id:, slug:, created:, chain:, sources:)
    dir = File.join(home, "store", "#{id}--#{slug}")
    FileUtils.mkdir_p(dir)
    fm = +"---\n"
    fm << "id: '#{id}'\n"
    fm << "intent: #{slug.capitalize} intent\n"
    fm << "sources: #{sources.inspect}\n"
    fm << "chain: #{chain.inspect}\n"
    fm << "created: #{created}\n" if created
    fm << "author: human\n"
    fm << "tags:\n- plastic\n"
    fm << "---\n\n"
    File.write(File.join(dir, "#{id}--#{slug}.md"), "#{fm}## Intent\n#{slug.capitalize} intent body.\n")
  end

  def write_snapshot(home, id, events:, state:)
    dir = Dir.glob(File.join(home, "store", "#{id}--*")).first
    lines = events.map { |e| JSON.generate("kind" => "event", **e.transform_keys(&:to_s), "payload" => {}) }
    lines << JSON.generate("kind" => "state", **state.transform_keys(&:to_s))
    File.write(File.join(dir, "savepoint.jsonl"), lines.map { |l| "#{l}\n" }.join)
  end

  # Copies the fixture tree into a second independent tmpdir (its own
  # plastic.db will live alongside this copy, never shared with the first).
  def clone_store(source_home)
    dest = Dir.mktmpdir("plastic-db-rebuild-store-clone")
    FileUtils.rm_rf(dest)
    FileUtils.cp_r(source_home, dest)
    dest
  end

  def rebuild_into(store_home, now: Time.utc(2026, 7, 9, 12, 0, 0))
    conn = Plastic::DB.connect(store_home)
    Plastic::DB::Rebuild.rebuild!(conn, store_home: store_home, now: now)
    conn
  end

  # --- AC3: byte-identical canonical dump across two independent rebuilds ----

  def test_two_independent_rebuilds_of_the_same_fixture_are_byte_identical
    @store_a = build_fixture_store
    @store_b = clone_store(@store_a)

    # Deliberately DIFFERENT wall-clock `now:` for each run: determinism must
    # hold on file content alone, never on when rebuild happened to run.
    conn_a = rebuild_into(@store_a, now: Time.utc(2026, 7, 9, 12, 0, 0))
    conn_b = rebuild_into(@store_b, now: Time.utc(2027, 3, 3, 3, 3, 3))

    dump_a = Plastic::DB::Rebuild.canonical_dump(conn_a)
    dump_b = Plastic::DB::Rebuild.canonical_dump(conn_b)

    refute_empty dump_a
    assert_equal dump_a, dump_b, "two independent rebuilds of the same fixture store must be byte-identical"
  end

  # --- rebuild twice into the SAME file is idempotent ------------------------

  def test_rebuild_twice_into_the_same_file_is_idempotent
    @store_a = build_fixture_store
    conn = Plastic::DB.connect(@store_a)

    Plastic::DB::Rebuild.rebuild!(conn, store_home: @store_a, now: Time.utc(2026, 7, 9))
    first_dump = Plastic::DB::Rebuild.canonical_dump(conn)

    Plastic::DB::Rebuild.rebuild!(conn, store_home: @store_a, now: Time.utc(2026, 7, 10))
    second_dump = Plastic::DB::Rebuild.canonical_dump(conn)

    assert_equal first_dump, second_dump
  end

  # --- Q5 restore: authoritative status/quadrant/queue/batch from snapshot --

  def test_q5_restore_authoritative_fields_from_snapshot
    @store_a = build_fixture_store
    conn = rebuild_into(@store_a)

    intent1 = Plastic::DB.by_status(@store_a, "active").find { |h| h["intent_id"] == "1" }
    refute_nil intent1
    assert_equal "quick_win", intent1["quadrant"]
    assert_equal ["1"], Plastic::DB.by_queue(@store_a, "launch-batch", batch: 2).map { |h| h["intent_id"] }

    intent2 = Plastic::DB.by_status(@store_a, "done").find { |h| h["intent_id"] == "2" }
    refute_nil intent2
    assert_nil intent2["quadrant"]
    assert_equal [], Plastic::DB.by_queue(@store_a, "launch-batch", batch: nil).reject { |h| h["intent_id"] == "1" }

    conn.close
  end

  # --- files win: a stale derived row with no matching file disappears ------

  def test_stale_derived_row_with_no_matching_file_is_gone_after_rebuild
    @store_a = build_fixture_store
    conn = Plastic::DB.connect(@store_a)

    Plastic::DB.with_write(conn) do |c|
      c.execute(
        "INSERT INTO intents (intent_id, title, created_at, updated_at) VALUES (?, ?, ?, ?)",
        ["ghost", "Stale ghost row", "2020-01-01T00:00:00Z", "2020-01-01T00:00:00Z"]
      )
    end
    assert conn.execute("SELECT id FROM intents WHERE intent_id = 'ghost'").first

    Plastic::DB::Rebuild.rebuild!(conn, store_home: @store_a, now: Time.utc(2026, 7, 9))

    assert_nil conn.execute("SELECT id FROM intents WHERE intent_id = 'ghost'").first,
               "a stale derived row for a file that no longer exists must be gone after rebuild!"
  end

  # --- content-derived timestamps, never wall-clock --------------------------

  def test_intent_timestamps_are_content_derived_from_frontmatter_created
    @store_a = build_fixture_store
    conn = rebuild_into(@store_a, now: Time.utc(2099, 12, 31))

    row1 = conn.execute("SELECT created_at, updated_at FROM intents WHERE intent_id = '1'").first
    assert_equal ["2026-01-01T00:00:00Z", "2026-01-01T00:00:00Z"], row1,
                 "created_at must derive from frontmatter created:, not the injected wall-clock now:"
  end

  def test_intent_missing_created_falls_back_to_the_fixed_constant
    @store_a = build_fixture_store
    conn = rebuild_into(@store_a)

    row3 = conn.execute("SELECT created_at FROM intents WHERE intent_id = '3'").first
    refute_nil row3.first
    assert row3.first.start_with?("19"), "a missing created: must fall back to the documented fixed constant, not nil/now"
  end

  # --- fail-open --------------------------------------------------------------

  def test_rebuild_fails_open_on_nil_conn
    assert_nil Plastic::DB::Rebuild.rebuild!(nil, store_home: "/nonexistent")
  end

  def test_canonical_dump_fails_open_on_nil_conn
    assert_nil Plastic::DB::Rebuild.canonical_dump(nil)
  end

  # --- facade wrapper ----------------------------------------------------------

  def test_facade_rebuild_and_canonical_dump_delegate_to_rebuild_module
    @store_a = build_fixture_store
    result = Plastic::DB.rebuild!(@store_a, now: Time.utc(2026, 7, 9))
    assert result

    dump = Plastic::DB.canonical_dump(@store_a)
    refute_nil dump
    assert_includes dump, "1|"
  end

  def test_facade_rebuild_fails_open_when_sqlite3_unavailable
    @store_a = build_fixture_store
    assert_nil Plastic::DB.rebuild!(@store_a, available: false)
    assert_nil Plastic::DB.canonical_dump(@store_a, available: false)
  end
end
