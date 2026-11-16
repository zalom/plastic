# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/config"

class ConfigRowsTest < Plastic::TestCase
  include ConfigHomes

  def rows = Plastic::Config::Rows.new(@plastic_home)

  def test_the_settings_of_a_scope_read_back_as_a_nested_hash
    seed_config(@plastic_home, "global:\n  runner:\n    stop_hook: true\n  screens: false\n")

    assert_equal({ "runner" => { "stop_hook" => true }, "screens" => false }, rows.scope("global"))
  end

  def test_a_scope_with_no_rows_reads_as_empty
    seed_config(@plastic_home, "global:\n  screens: false\n")

    assert_empty rows.scope("codex")
  end

  def test_a_missing_plastic_db_reads_as_empty_and_creates_no_file
    assert_empty rows.scope("global")
    refute_path_exists File.join(@plastic_home, "plastic.db")
  end

  def test_a_plastic_db_behind_the_settings_table_reads_as_empty
    SQLite3::Database.new(File.join(@plastic_home, "plastic.db")) { |db| db.execute("CREATE TABLE other(a)") }

    assert_empty rows.scope("global")
  end

  def test_a_database_held_by_a_writer_reads_the_rows_committed_before
    seed_config(@plastic_home, "global:\n  screens: false\n")
    writer = SQLite3::Database.new(File.join(@plastic_home, "plastic.db"))
    writer.execute("BEGIN IMMEDIATE")

    assert_equal({ "screens" => false }, rows.scope("global"))
  ensure
    writer&.close
  end

  def test_the_printed_hash_of_a_file_reads_back
    seed_config(@plastic_home, "global:\n  screens: false\n")

    assert_equal Digest::SHA256.file(File.join(@plastic_home, "config.yml")).hexdigest, rows.printed("config.yml")
  end

  def test_a_file_never_printed_has_no_hash
    seed_config(@plastic_home, "global:\n  screens: false\n")

    assert_nil rows.printed("other.yml")
  end
end
