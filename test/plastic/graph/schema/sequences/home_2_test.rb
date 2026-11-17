# frozen_string_literal: true

require "digest"
require "sqlite3"
require_relative "../../../../test_helper"

# Home migration 2 is frozen: a digest pins its text, and it runs on a real database.
class SchemaHome2Test < Plastic::TestCase
  Sequences = Plastic::Graph::SchemaSequences
  Home1 = Plastic::Graph::SchemaHome1
  Home2 = Plastic::Graph::SchemaHome2

  PINNED = "1a521c37f40c98f7a9d7b0f1f8d54bfbbe520ae42de99a71e895808306a3caba"

  def migrated_database
    SQLite3::Database.new(":memory:").tap do |database|
      database.execute_batch(Home1::TEXT.fetch(:local))
      database.execute("INSERT INTO routine_runs (store, tool, subject) VALUES ('s', 'intent new', 'a')")
      database.execute("PRAGMA user_version = 1")
      Sequences.migrate(database, Sequences::SEQUENCES.fetch(:home), :local)
    end
  end

  def table_names(database) = database.execute("SELECT name FROM sqlite_master WHERE type = 'table'").flatten

  def test_the_text_of_the_landed_migration_is_pinned_by_its_digest
    assert_equal PINNED, Digest::SHA256.hexdigest(Home2.texts.join("\n--\n"))
  end

  def test_the_migration_never_reads_the_live_schema
    source = File.read(File.join(__dir__, "../../../../../lib/plastic/graph/schema/sequences/home_2.rb"))

    refute_match(/Schema\.(fetch|ddl|prepare)/, source)
  end

  def test_the_routine_runs_table_becomes_command_runs_with_every_row
    database = migrated_database

    assert_equal [["s", "intent new", "a"]], database.execute("SELECT store, tool, subject FROM command_runs")
    refute_includes table_names(database), "routine_runs"
  end

  def test_the_backups_table_is_dropped
    refute_includes table_names(migrated_database), "backups"
  end

  def test_the_home_stamp_is_the_number_of_the_newest_migration_it_ran
    assert_equal Sequences.newest(:home), migrated_database.get_first_value("PRAGMA user_version")
  end
end
