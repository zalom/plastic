# frozen_string_literal: true

require_relative "../../../test_helper"

class LocalTest < Plastic::TestCase
  Database = Plastic::Graph::Database

  def machine = File.join(@home, "machine")

  def unmigrated_home
    FileUtils.mkdir_p(machine)
    SQLite3::Database.new(File.join(machine, "local.db")).tap { |db| db.execute("CREATE TABLE routine_runs(store TEXT)") }.close
  end

  def first_use = Database.open_local(machine).fetch(:local).rows("SELECT 1")

  def test_the_machine_database_is_plastic_db
    assert_equal File.join(machine, "plastic.db"), Database.open_local(machine).fetch(:local).path
  end

  def test_a_home_with_only_local_db_is_refused_as_behind
    unmigrated_home

    assert_raises(Plastic::Graph::Behind) { first_use }
  end

  def test_a_command_on_an_unmigrated_home_renames_nothing_and_creates_no_plastic_db
    unmigrated_home
    assert_raises(Plastic::Graph::Behind) { first_use }

    assert_equal ["local.db"], Dir.children(machine)
  end

  def test_a_home_with_no_database_gets_a_new_plastic_db
    FileUtils.mkdir_p(machine)
    first_use

    assert_equal ["plastic.db"], Dir.children(machine).grep(/\.db\z/)
  end
end
