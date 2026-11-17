# frozen_string_literal: true

require "sqlite3"
require_relative "../../../../test_helper"

# Each migration and its stamp commit together under the write lock.
class SchemaSequencesTransactionTest < Plastic::TestCase
  Sequences = Plastic::Graph::SchemaSequences

  def setup
    super
    @path = File.join(Dir.mktmpdir, "a.db")
  end

  def migration(&apply) = Sequences::Migration.new(1, apply, {})

  def test_a_second_runner_that_waited_for_the_lock_finds_the_database_current_and_runs_nothing
    applied = []
    step = migration { |_connection, _key| applied << true }
    first, second = Array.new(2) { SQLite3::Database.new(@path) }
    [first, second].each { |connection| Sequences.migrate(connection, [step], :work) }

    assert_equal [1, 1], [applied.size, second.get_first_value("PRAGMA user_version")]
  end

  def test_a_migration_already_stamped_is_skipped_when_a_longer_sequence_runs
    applied = []
    first = migration { |_connection, _key| applied << 1 }
    second = Sequences::Migration.new(2, ->(_connection, _key) { applied << 2 }, {})
    database = SQLite3::Database.new(@path)
    Sequences.migrate(database, [first], :work)
    Sequences.migrate(database, [first, second], :work)

    assert_equal [[1, 2], 2], [applied, database.get_first_value("PRAGMA user_version")]
  end

  def test_a_migration_stamped_while_the_runner_waited_for_the_lock_is_not_applied_again
    applied = []
    step = migration { |_connection, _key| applied << true }
    database = SQLite3::Database.new(@path)
    database.execute("PRAGMA user_version = 1")
    Sequences.send(:apply_once, database, step, :work)

    assert_empty applied
  end

  def test_a_runner_that_cannot_get_the_write_lock_raises_busy_and_changes_nothing
    holder = SQLite3::Database.new(@path)
    holder.execute("BEGIN IMMEDIATE")
    waiting = SQLite3::Database.new(@path)
    waiting.busy_timeout = 0
    step = migration { |connection, _key| connection.execute("CREATE TABLE t (a)") }

    assert_raises(SQLite3::BusyException) { Sequences.migrate(waiting, [step], :work) }
    holder.execute("ROLLBACK")

    assert_equal [0, 0], [waiting.get_first_value("PRAGMA user_version"), waiting.get_first_value("SELECT COUNT(*) FROM sqlite_master")]
  end

  def test_a_migration_that_raises_after_its_statements_leaves_neither_the_tables_nor_the_stamp
    database = SQLite3::Database.new(@path)
    step = migration do |connection, _key|
      connection.execute("CREATE TABLE t (a)")
      raise "killed"
    end

    assert_raises(RuntimeError) { Sequences.migrate(database, [step], :work) }
    assert_equal [0, 0], [database.get_first_value("PRAGMA user_version"), database.get_first_value("SELECT COUNT(*) FROM sqlite_master")]
  end
end
