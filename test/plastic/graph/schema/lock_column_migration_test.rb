# frozen_string_literal: true

require "sqlite3"
require "tmpdir"
require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/schema"
require_relative "../../../../lib/plastic/graph/database"

class SchemaLockColumnMigrationTest < Minitest::Test
  HELD = "local.db is held by another process; run the command again when it is free"

  def setup
    @dir = Dir.mktmpdir("lock-column")
    @path = File.join(@dir, "local.db")
    @file = SQLite3::Database.new(@path)
    @file.execute_batch(Plastic::Graph::Schema.fetch(:local))
    @file.execute("ALTER TABLE locks RENAME COLUMN locked_at TO taken_at") if columns.include?("locked_at")
    @file.execute("INSERT INTO locks (store, intent_id, session_id, mode, taken_at, renewed_at) VALUES ('s', '1', 'x', 'auto', 'T0', 'T1')")
  end

  def teardown
    @file.close
    FileUtils.remove_entry(@dir)
  end

  def prepare(connection = @file) = Plastic::Graph::Schema.prepare(connection, Plastic::Graph::Schema.fetch(:local))

  def columns = @file.execute("PRAGMA table_info(locks)").map { |column| column[1] }

  def test_a_locks_table_with_the_older_column_gets_the_new_name
    prepare

    assert_includes columns, "locked_at"
    refute_includes columns, "taken_at"
  end

  def test_the_lock_row_keeps_its_values_across_the_rename
    prepare

    assert_equal [["x", "T0", "T1"]], @file.execute("SELECT session_id, locked_at, renewed_at FROM locks")
  end

  def test_a_second_prepare_changes_nothing
    prepare
    before = @file.get_first_value("SELECT sql FROM sqlite_master WHERE name = 'locks'")
    prepare

    assert_equal before, @file.get_first_value("SELECT sql FROM sqlite_master WHERE name = 'locks'")
  end

  def test_a_database_made_with_the_current_schema_is_left_as_it_is
    current = SQLite3::Database.new(":memory:")
    prepare(current)

    assert_includes current.execute("PRAGMA table_info(locks)").map { |column| column[1] }, "locked_at"
  end

  def test_a_database_held_by_another_process_stops_with_the_plain_line_and_keeps_the_older_column
    holder = SQLite3::Database.new(@path)
    holder.execute("BEGIN IMMEDIATE")
    error = assert_raises(Plastic::Graph::Database::Error) { prepare(SQLite3::Database.new(@path)) }
    holder.execute("ROLLBACK")

    assert_equal [HELD, true], [error.message, columns.include?("taken_at")]
  end

  def test_the_command_that_follows_a_held_database_renames_the_column_and_keeps_the_lock
    holder = SQLite3::Database.new(@path)
    holder.execute("BEGIN IMMEDIATE")
    assert_raises(Plastic::Graph::Database::Error) { prepare(SQLite3::Database.new(@path)) }
    holder.execute("ROLLBACK")
    prepare

    assert_equal [["x", "T0"]], @file.execute("SELECT session_id, locked_at FROM locks")
  end
end
