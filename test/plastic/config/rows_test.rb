# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/config"

class ConfigRowsTest < Plastic::TestCase
  include ConfigHomes

  def rows = Plastic::Wiring.rows(@plastic_home)

  def test_the_settings_of_a_scope_read_back_as_a_nested_hash
    seed_config(@plastic_home, "global:\n  runner:\n    stop_hook: true\n  screens: false\n")

    assert_equal({ "runner" => { "stop_hook" => true }, "screens" => false }, rows.scope("global"))
  end

  def test_a_scope_with_no_rows_reads_as_empty
    seed_config(@plastic_home, "global:\n  screens: false\n")

    assert_empty rows.scope("codex")
  end

  def test_a_missing_plastic_db_reads_as_empty_and_creates_no_file
    Dir.mktmpdir do |dir|
      assert_empty Plastic::Wiring.rows(dir).scope("global")
      refute_path_exists File.join(dir, "plastic.db")
    end
  end

  def test_a_plastic_db_behind_the_settings_table_reads_as_empty
    Dir.mktmpdir do |dir|
      SQLite3::Database.new(File.join(dir, "plastic.db")) { |db| db.execute("CREATE TABLE other(a)") }

      assert_empty Plastic::Wiring.rows(dir).scope("global")
    end
  end

  def test_the_printed_hash_of_a_file_reads_back
    seed_config(@plastic_home, "global:\n  screens: false\n")

    assert_equal Digest::SHA256.file(File.join(@plastic_home, "config.yml")).hexdigest, rows.printed("config.yml")
  end

  def test_a_file_never_printed_has_no_hash
    seed_config(@plastic_home, "global:\n  screens: false\n")

    assert_nil rows.printed("other.yml")
  end

  def test_a_key_under_a_scalar_replaces_it_and_a_key_beside_a_hash_joins_it
    tree = { "a" => 1, "b" => { "x" => 1 } }
    Plastic::Config::Rows.insert(tree, "a.deep", 2)
    Plastic::Config::Rows.insert(tree, "b.y", 3)

    assert_equal({ "a" => { "deep" => 2 }, "b" => { "x" => 1, "y" => 3 } }, tree)
  end
end
