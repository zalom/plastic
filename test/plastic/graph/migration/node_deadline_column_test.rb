# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../test_helpers/previous_store"

# Migration 20261123154000 adds the nullable column deadline to the nodes table, and its down drops it again.
class GraphNodeDeadlineColumnTest < Plastic::TestCase
  include BackupHomes
  include PreviousStore

  NOW = Time.utc(2026, 11, 23, 16, 0, 0)
  ROW = "INSERT INTO nodes (intent_id, id, kind, title, state, findings, origin_id) VALUES ('1', 'n1', 'work', 'Build', 'done', 'green', 'o')"

  def columns(home) = alpha_rows(home, "work_graph.db", "SELECT name FROM pragma_table_info('nodes')").flatten

  def seeded
    previous_home.tap { |home| SQLite3::Database.open(alpha_file(home, "work_graph.db")) { |database| database.execute(ROW) } }
  end

  def down(home) = Plastic::Graph::MigrationDown.new(home, "alpha", NOW).call

  def fresh_columns
    home = fresh_home
    Plastic::Graph::Database::ConnectionPool.release(home)
    columns(home)
  end

  def test_a_new_store_has_a_deadline_column_on_a_node
    assert_includes fresh_columns, "deadline"
  end

  def test_the_migration_has_no_switch
    refute_includes Plastic::Graph::MigrationList::HELD.keys, DEADLINE
  end

  def test_the_migration_adds_the_column_and_leaves_the_layout_of_a_new_store
    home = previous_home
    before = columns(home)
    migrate_store(home)

    assert_equal [false, fresh_columns], [before.include?("deadline"), columns(home)]
  end

  def test_the_migration_keeps_each_node_row_with_no_deadline
    home = seeded
    migrate_store(home)

    assert_equal [[["1", "n1", "Build", nil]], true], [alpha_rows(home, "work_graph.db", "SELECT intent_id, id, title, deadline FROM nodes"), recorded(home).include?(DEADLINE)]
  end

  def test_a_down_drops_the_column_and_removes_the_version
    home = seeded.tap { |seeded_home| migrate_store(seeded_home) }
    3.times { down(home) }
    undone = down(home)

    assert_equal [DEADLINE, {}, false, false], [undone.version, undone.moved, columns(home).include?("deadline"), recorded(home).include?(DEADLINE)]
  end

  def test_a_down_and_an_update_give_back_the_migrated_store
    home = seeded.tap { |seeded_home| migrate_store(seeded_home) }
    before = alpha_rows(home, "work_graph.db", "SELECT * FROM nodes")
    down(home)
    migrate_store(home)

    assert_equal [fresh_columns, before], [columns(home), alpha_rows(home, "work_graph.db", "SELECT * FROM nodes")]
  end
end
