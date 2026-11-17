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
    Dir.mktmpdir do |dir|
      assert_empty Plastic::Config::Rows.new(dir).scope("global")
      refute_path_exists File.join(dir, "plastic.db")
    end
  end

  def test_a_plastic_db_behind_the_settings_table_reads_as_empty
    Dir.mktmpdir do |dir|
      SQLite3::Database.new(File.join(dir, "plastic.db")) { |db| db.execute("CREATE TABLE other(a)") }

      assert_empty Plastic::Config::Rows.new(dir).scope("global")
    end
  end

  def failing_with(failure)
    original = Plastic::Graph::Database.method(:open_local)
    Plastic::Graph::Database.define_singleton_method(:open_local, &failure)
    yield
  ensure
    Plastic::Graph::Database.define_singleton_method(:open_local, original)
  end

  def test_an_error_that_is_not_a_database_error_is_not_swallowed
    seed_config(@plastic_home, "global:\n  screens: false\n")
    broken = ->(*) { raise ArgumentError, "a bug" }

    failing_with(broken) { assert_raises(ArgumentError) { rows.scope("global") } }
  end

  def test_a_locked_database_reads_as_empty
    seed_config(@plastic_home, "global:\n  screens: false\n")
    busy = ->(*) { raise SQLite3::BusyException, "locked" }

    failing_with(busy) { assert_empty rows.scope("global") }
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
