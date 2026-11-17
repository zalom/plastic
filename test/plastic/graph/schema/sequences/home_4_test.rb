# frozen_string_literal: true

require "digest"
require "sqlite3"
require_relative "../../../../test_helper"

# Home migration 4 is frozen: a digest pins its text, and it runs on a real database.
class SchemaHome4Test < Plastic::TestCase
  Sequences = Plastic::Graph::SchemaSequences
  Home4 = Plastic::Graph::SchemaHome4

  PINNED = "fdde25a4fe1512c248bebc29ce54a16419805f7b332487ac5bdb55c1f1feca94"

  def migrated_database
    dir = Dir.mktmpdir
    SQLite3::Database.new(File.join(dir, "plastic.db")).tap do |database|
      Plastic::Graph::SchemaHome1::TEXT.fetch(:local).then { |sql| database.execute_batch(sql) }
      database.execute("PRAGMA user_version = 1")
      Sequences.migrate(database, Sequences::SEQUENCES.fetch(:home), :local)
    end
  end

  def test_the_text_of_the_landed_migration_is_pinned_by_its_digest
    assert_equal PINNED, Digest::SHA256.hexdigest(Home4.texts.join("\n--\n"))
  end

  def test_the_migration_never_reads_the_live_schema
    source = File.read(File.join(__dir__, "../../../../../lib/plastic/graph/schema/sequences/home_4.rb"))

    refute_match(/Schema\.(fetch|ddl|prepare)/, source)
  end

  def test_the_locks_table_is_dropped_and_the_others_stay
    names = migrated_database.execute("SELECT name FROM sqlite_master WHERE type = 'table'").flatten

    refute_includes names, "locks"
    assert_includes names, "sessions"
    assert_includes names, "command_runs"
  end

  def test_the_stamp_is_four
    assert_equal 4, migrated_database.get_first_value("PRAGMA user_version")
  end

  def test_a_second_run_changes_nothing
    database = migrated_database
    Home4.apply(database, :local)

    assert_equal 4, database.get_first_value("PRAGMA user_version")
  end
end
