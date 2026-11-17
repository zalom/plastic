# frozen_string_literal: true

require "digest"
require "sqlite3"
require_relative "../../../../test_helper"

# Home migration 3 is frozen: a digest pins its text, and it runs on a real database.
class SchemaHome3Test < Plastic::TestCase
  Sequences = Plastic::Graph::SchemaSequences
  Home3 = Plastic::Graph::SchemaHome3

  PINNED = "d1611043674e0201f6ee9dfae21d0d899b3f19903a77a1d8d317d74197b42d97"

  def migrated_database(config_text)
    dir = Dir.mktmpdir
    File.write(File.join(dir, "config.yml"), config_text) if config_text
    SQLite3::Database.new(File.join(dir, "plastic.db")).tap do |database|
      Plastic::Graph::SchemaHome1::TEXT.fetch(:local).then { |sql| database.execute_batch(sql) }
      database.execute("PRAGMA user_version = 1")
      Sequences.migrate(database, Sequences::SEQUENCES.fetch(:home), :local)
    end
  end

  def test_the_text_of_the_landed_migration_is_pinned_by_its_digest
    assert_equal PINNED, Digest::SHA256.hexdigest(Home3.texts.join("\n--\n"))
  end

  def test_the_migration_never_reads_the_live_schema
    source = File.read(File.join(__dir__, "../../../../../lib/plastic/graph/schema/sequences/home_3.rb"))

    refute_match(/Schema\.(fetch|ddl|prepare)/, source)
  end

  def test_the_settings_and_printed_tables_are_created
    names = migrated_database(nil).execute("SELECT name FROM sqlite_master WHERE type = 'table'").flatten

    assert_includes names, "settings"
    assert_includes names, "printed"
  end

  def test_the_config_file_is_imported_once_into_the_settings_rows
    database = migrated_database("global:\n  screens: false\nharnesses:\n  codex:\n    statusline: true\n")

    assert_equal [["codex", "statusline", "true"], ["global", "screens", "false"]], database.execute("SELECT scope, key, value FROM settings ORDER BY scope")
  end

  def test_anchors_and_merge_keys_are_resolved_to_plain_values
    text = "global:\n  agents: &shared\n    models:\n      plastic-executor: haiku\n" \
           "harnesses:\n  claude-code:\n    agents:\n      <<: *shared\n"
    rows = migrated_database(text).execute("SELECT scope, key, value FROM settings ORDER BY scope")

    assert_equal [["claude-code", "agents.models.plastic-executor", "\"haiku\""], ["global", "agents.models.plastic-executor", "\"haiku\""]], rows
  end

  def test_a_file_that_does_not_parse_imports_nothing
    assert_empty migrated_database("runner: [\n").execute("SELECT * FROM settings")
  end

  def test_a_file_holding_a_plain_list_imports_nothing
    assert_empty migrated_database("- a\n- b\n").execute("SELECT * FROM settings")
  end

  def test_a_home_with_no_config_file_imports_nothing
    assert_empty migrated_database(nil).execute("SELECT * FROM settings")
  end

  def test_the_stamp_is_the_newest_home_number
    assert_equal Sequences.newest(:home), migrated_database(nil).get_first_value("PRAGMA user_version")
  end
end
