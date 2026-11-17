# frozen_string_literal: true

require "digest"
require "sqlite3"
require_relative "../../../../test_helper"

# Home migration 1 is frozen: a digest pins its text, and the lock column rename runs on a real database.
class SchemaHome1Test < Plastic::TestCase
  Sequences = Plastic::Graph::SchemaSequences
  Home1 = Plastic::Graph::SchemaHome1

  PINNED = "f183f41fb12cac387148aa5f0fc4698e6b88f400bf2b2ff361210a44946eba67"

  def migrate(database) = Sequences.migrate(database, Sequences::SEQUENCES.fetch(:home).first(1), :local)

  def test_the_text_of_the_landed_migration_is_pinned_by_its_digest
    assert_equal PINNED, Digest::SHA256.hexdigest(Home1.texts.join("\n--\n"))
  end

  def test_the_migration_never_reads_the_live_schema
    source = File.read(File.join(__dir__, "../../../../../lib/plastic/graph/schema/sequences/home_1.rb"))

    refute_match(/Schema\.(fetch|ddl|prepare)/, source)
  end

  def test_the_older_time_column_of_the_locks_table_is_renamed
    database = SQLite3::Database.new(":memory:")
    database.execute_batch(Home1::TEXT.fetch(:local))
    database.execute("ALTER TABLE locks RENAME COLUMN locked_at TO taken_at")
    migrate(database)

    assert_includes database.execute("PRAGMA table_info(locks)").map { |column| column[1] }, "locked_at"
  end

  def test_an_empty_file_gets_the_tables_and_the_stamp
    database = SQLite3::Database.new(":memory:")
    migrate(database)

    assert_equal [Home1::TABLES.fetch("local").sort, 1],
      [database.execute("SELECT name FROM sqlite_master WHERE type = 'table'").flatten.sort & Home1::TABLES.fetch("local"), database.get_first_value("PRAGMA user_version")]
  end
end
