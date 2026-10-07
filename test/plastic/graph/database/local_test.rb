# frozen_string_literal: true

require_relative "../../../test_helper"

class LocalTest < Plastic::TestCase
  def machine = File.join(@home, "machine")

  def home_db_from_before
    Plastic::Graph::Database.new(File.join(machine, "home.db"), Plastic::Graph::Schema.fetch(:local)).transaction do |batch|
      batch.insert(:routine_runs, { store: "s", tool: "t", subject: "a" })
    end
    Plastic::Graph::Database::ConnectionPool.release(machine)
  end

  def first_use = Plastic::Graph::Database.open_local(machine).fetch(:local).tap { |local| local.rows("SELECT 1") }

  def test_a_home_db_left_from_before_becomes_local_db_on_first_use
    home_db_from_before

    assert_equal ["a"], first_use.rows("SELECT subject FROM routine_runs").map { |row| row.fetch("subject") }
    assert_equal [false, true], [File.exist?(File.join(machine, "home.db")), File.exist?(File.join(machine, "local.db"))]
  end

  def test_only_the_call_that_renamed_the_file_says_so
    home_db_from_before

    assert_equal [["home.db renamed to local.db"], []], [first_use.phrases, first_use.phrases]
  end

  def test_opening_renames_nothing_before_the_first_use
    home_db_from_before
    Plastic::Graph::Database.open_local(machine)

    assert_equal [true, false], [File.exist?(File.join(machine, "home.db")), File.exist?(File.join(machine, "local.db"))]
  end
end
