# frozen_string_literal: true

require "digest"
require "sqlite3"
require_relative "../../../../test_helper"

# Store migration 3 is frozen: a digest pins its text, and it runs on a real work database.
class SchemaStore3Test < Plastic::TestCase
  Sequences = Plastic::Graph::SchemaSequences
  Store1 = Plastic::Graph::SchemaStore1

  PINNED = "0" * 64

  SAVEPOINTS = [
    ["1", 1, "2026-10-20T08:00:00+02:00", "Opened: Alpha", "o", nil],
    ["1", 2, "2026-10-20T09:00:00+02:00", "Spec written", "o", "s-1"],
    ["1", 3, nil, "free text", "o", nil],
    ["2", 1, "2026-10-21T08:00:00+02:00", "Opened: Beta", "o", "s-2"]
  ].freeze

  def setup
    super
    @database = SQLite3::Database.new(":memory:")
    @database.execute_batch(Store1::Layout::TEXT.fetch(:work))
    @database.execute_batch(Plastic::Graph::SchemaStore2::TEXT.fetch(:work))
    @database.execute("PRAGMA user_version = 2")
    SAVEPOINTS.each { |row| @database.execute("INSERT INTO savepoints (intent_id, position, at, text, origin_id, session_id) VALUES (?, ?, ?, ?, ?, ?)", row) }
  end

  def migrate = Sequences.migrate(@database, Sequences::SEQUENCES.fetch(:store), :work)

  def log = @database.execute("SELECT intent_id, position, at, kind, session_id, phase, node, path, sha256, text FROM work_log ORDER BY intent_id, position")

  def tables = @database.execute("SELECT name FROM sqlite_master WHERE type = 'table'").flatten

  def test_the_text_of_the_landed_migration_is_pinned_by_its_digest
    assert_equal PINNED, Digest::SHA256.hexdigest(Plastic::Graph::SchemaStore3.texts.join("\n--\n"))
  end

  def test_the_migration_never_reads_the_live_schema
    source = File.read(File.join(__dir__, "../../../../../lib/plastic/graph/schema/sequences/store_3.rb"))

    refute_match(/Schema\.(fetch|ddl|prepare)/, source)
  end

  def test_every_savepoint_row_becomes_one_noted_row_with_its_text_and_time
    migrate

    assert_equal [["1", 1, "2026-10-20T08:00:00+02:00", "noted", nil, "", "", "", "", "Opened: Alpha"],
      ["1", 2, "2026-10-20T09:00:00+02:00", "noted", "s-1", "", "", "", "", "Spec written"],
      ["1", 3, nil, "noted", nil, "", "", "", "", "free text"],
      ["2", 1, "2026-10-21T08:00:00+02:00", "noted", "s-2", "", "", "", "", "Opened: Beta"]], log
  end

  def test_the_count_of_rows_is_the_same_before_and_after
    before = @database.get_first_value("SELECT count(*) FROM savepoints")
    migrate

    assert_equal before, @database.get_first_value("SELECT count(*) FROM work_log")
  end

  def test_the_savepoints_table_is_dropped_and_the_stamp_is_the_number
    migrate

    assert_equal [3, false, true], [@database.get_first_value("PRAGMA user_version"), tables.include?("savepoints"), tables.include?("work_log")]
  end

  def test_a_connection_that_returns_rows_by_name_runs_the_migration_too
    @database.results_as_hash = true
    migrate
    @database.results_as_hash = false

    assert_equal [3, 4], [@database.get_first_value("PRAGMA user_version"), log.size]
  end

  def test_a_second_run_changes_nothing
    migrate
    before = log
    Plastic::Graph::SchemaStore3.apply(@database, :work)

    assert_equal before, log
  end

  def test_a_migrated_work_database_has_the_table_of_a_new_one
    migrate
    fresh = SQLite3::Database.new(":memory:")
    fresh.execute_batch(Plastic::Graph::Schema.fetch(:work))
    sql = ->(database) { database.get_first_value("SELECT sql FROM sqlite_master WHERE name = 'work_log'") }

    assert_equal sql.call(fresh), sql.call(@database)
  end
end
