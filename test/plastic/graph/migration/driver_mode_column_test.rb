# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../test_helpers/previous_store"

# Migration 20261124173000 adds the nullable column mode to the drivers table, and its down drops it again.
class GraphDriverModeColumnTest < Plastic::TestCase
  include BackupHomes
  include PreviousStore

  NOW = Time.utc(2026, 11, 24, 18, 0, 0)
  ROW = "INSERT INTO drivers (intent_id, origin_id, session_id, claimed_at, seen_at) VALUES ('1', 'o', 's-1', 'then', 'then')"

  def columns(home) = alpha_rows(home, "work_graph.db", "SELECT name FROM pragma_table_info('drivers')").flatten

  def seeded
    previous_home.tap { |home| SQLite3::Database.open(alpha_file(home, "work_graph.db")) { |database| database.execute(ROW) } }
  end

  def down(home) = Plastic::Graph::MigrationDown.new(home, "alpha", NOW).call

  def fresh_columns
    home = fresh_home
    Plastic::Graph::Database::ConnectionPool.release(home)
    columns(home)
  end

  def test_a_new_store_has_a_mode_column_on_a_driver
    assert_includes fresh_columns, "mode"
  end

  def test_the_migration_adds_the_column_and_leaves_the_layout_of_a_new_store
    home = previous_home
    before = columns(home)
    migrate_store(home)

    assert_equal [false, fresh_columns], [before.include?("mode"), columns(home)]
  end

  def test_the_migration_keeps_each_driver_row_with_no_mode
    home = seeded
    migrate_store(home)

    assert_equal [[["1", "s-1", nil]], true], [alpha_rows(home, "work_graph.db", "SELECT intent_id, session_id, mode FROM drivers"), recorded(home).include?(DRIVER_MODE)]
  end

  def test_a_down_drops_the_column_and_removes_the_version
    home = seeded.tap { |seeded_home| migrate_store(seeded_home) }
    # The driver agent, work log text and ruling own id migrations are newer, so their downs come first.
    undone = 4.times.map { down(home) }.last

    assert_equal [DRIVER_MODE, {}, false, false], [undone.version, undone.moved, columns(home).include?("mode"), recorded(home).include?(DRIVER_MODE)]
  end

  def test_a_down_and_an_update_give_back_the_migrated_store
    home = seeded.tap { |seeded_home| migrate_store(seeded_home) }
    before = alpha_rows(home, "work_graph.db", "SELECT * FROM drivers")
    4.times { down(home) }
    migrate_store(home)

    assert_equal [fresh_columns, before], [columns(home), alpha_rows(home, "work_graph.db", "SELECT * FROM drivers")]
  end
end
