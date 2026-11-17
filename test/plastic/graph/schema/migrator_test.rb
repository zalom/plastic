# frozen_string_literal: true

require "tmpdir"
require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/schema/migrator"

class SchemaMigratorTest < Plastic::TestCase
  Migrator = Plastic::Graph::SchemaMigrator
  Connection = Plastic::Graph::Database::Connection
  FIXTURES = File.expand_path("../../../fixtures/migrations", __dir__)

  def setup
    super
    @path = File.join(Dir.mktmpdir("migrator", @home), "store.db")
    @connection = Connection.open(@path)
  end

  def teardown
    @connection.close
    super
  end

  def migration(name) = File.join(FIXTURES, "#{name}.sql")

  def stamp(connection = @connection) = connection.get_first_value("PRAGMA main.user_version")

  def titles(connection = @connection) = connection.execute("SELECT title FROM tickets").map { |row| row["title"] }

  def tables(connection = @connection) = connection.execute("SELECT name FROM sqlite_master WHERE type = 'table'").map { |row| row["name"] }

  def test_a_file_at_stamp_0_migrates_once
    Migrator.new(@connection, migration("add_tickets")).call

    assert_equal [1, ["first"]], [stamp, titles]
  end

  def test_a_second_run_does_nothing
    Migrator.new(@connection, migration("add_tickets")).call
    @connection.execute("INSERT INTO tickets(title) VALUES ('later')")
    Migrator.new(@connection, migration("add_tickets")).call

    assert_equal %w[first later], titles
  end

  def test_a_second_connection_that_read_0_reads_1_inside_its_own_transaction_and_runs_nothing
    second = Connection.open(@path)
    second.busy_timeout = 0
    Migrator.new(@connection, migration("add_tickets")).call
    second.execute("PRAGMA main.user_version")

    assert_nil Migrator.new(second, migration("add_tickets")).call
    assert_equal %w[first], titles(second)
  ensure
    second&.close
  end

  def test_a_file_at_stamp_2_raises_ahead_with_the_message_to_restore_the_backup
    @connection.execute("PRAGMA main.user_version = 2")

    error = assert_raises(Plastic::Graph::Ahead) { Migrator.new(@connection, migration("add_tickets")).call }

    assert_match(/restore the backup/, error.message)
    assert_empty tables
  end

  def test_a_failing_statement_leaves_stamp_0_and_the_file_unchanged
    assert_raises(SQLite3::ConstraintException) { Migrator.new(@connection, migration("add_tickets_then_fail")).call }

    assert_equal [0, []], [stamp, tables]
  end
end
