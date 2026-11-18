# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/graph/settings_database"

class SettingsDatabaseTest < Plastic::TestCase
  include ConfigHomes

  SQL = "SELECT scope FROM settings"

  def database(home = @plastic_home) = Plastic::Graph::SettingsDatabase.new(home)

  def test_a_missing_plastic_db_reads_as_empty_and_creates_no_file
    Dir.mktmpdir do |dir|
      assert_empty database(dir).rows(SQL)
      refute_path_exists File.join(dir, "plastic.db")
    end
  end

  def test_a_plastic_db_behind_the_settings_table_reads_as_empty
    Dir.mktmpdir do |dir|
      SQLite3::Database.new(File.join(dir, "plastic.db")) { |db| db.execute("CREATE TABLE other(a)") }

      assert_empty database(dir).rows(SQL)
    end
  end

  def test_the_rows_of_a_seeded_home_read_back
    seed_config(@plastic_home, "global:\n  screens: false\n")

    assert_equal [{ "scope" => "global" }], database.rows(SQL)
  end

  def test_a_write_lands_in_one_transaction
    seed_config(@plastic_home, "global:\n  screens: false\n")
    database.transaction { |batch| batch.add('DELETE FROM "settings"') }

    assert_empty database.rows(SQL)
  end

  def test_the_origin_id_is_the_one_of_the_home
    assert_equal Plastic::Graph::Origin.new(@plastic_home).id, database.origin_id
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

    failing_with(broken) { assert_raises(ArgumentError) { database.rows(SQL) } }
  end

  def test_a_locked_database_reads_as_empty
    seed_config(@plastic_home, "global:\n  screens: false\n")
    busy = ->(*) { raise SQLite3::BusyException, "locked" }

    failing_with(busy) { assert_empty database.rows(SQL) }
  end
end
