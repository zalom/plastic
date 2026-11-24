# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../test_helpers/previous_store"

# Migration 20261123170000 moves the input path of each node into the table node_inputs and drops the column input,
# and its down puts the first path back into the column and drops the table.
class GraphNodeInputsTableTest < Plastic::TestCase
  include BackupHomes
  include PreviousStore

  NOW = Time.utc(2026, 11, 23, 17, 0, 0)
  ROWS = [
    "INSERT INTO nodes (intent_id, id, kind, title, state, input, findings, origin_id) VALUES ('1', 'n1', 'work', 'Build', 'done', 'docs/a.md', 'green', 'o')",
    "INSERT INTO nodes (intent_id, id, kind, title, state, input, findings, origin_id) VALUES ('1', 'n2', 'work', 'Test', 'open', NULL, NULL, 'o')",
    "INSERT INTO nodes (intent_id, id, kind, title, state, input, findings, origin_id) VALUES ('1', 'n3', 'work', 'Ship', 'open', '', NULL, 'o')"
  ].freeze

  def columns(home, table = "nodes") = alpha_rows(home, "work_graph.db", "SELECT name FROM pragma_table_info('#{table}')").flatten

  def inputs(home) = alpha_rows(home, "work_graph.db", "SELECT intent_id, node_id, position, path, origin_id FROM node_inputs ORDER BY node_id, position")

  def seeded
    previous_home.tap { |home| SQLite3::Database.open(alpha_file(home, "work_graph.db")) { |database| ROWS.each { |row| database.execute(row) } } }
  end

  # The leftover work tables migration and the empty roadmap tables migration are the newest, so their downs come first.
  def down(home)
    7.times.map { Plastic::Graph::MigrationDown.new(home, "alpha", NOW).call }.last
  end

  def fresh_columns(table = "nodes")
    home = fresh_home
    Plastic::Graph::Database::ConnectionPool.release(home)
    columns(home, table)
  end

  def test_a_new_store_has_the_table_node_inputs_and_no_input_column_on_a_node
    assert_equal [%w[intent_id node_id origin_id path position], false], [fresh_columns("node_inputs").sort, fresh_columns.include?("input")]
  end

  def test_the_migration_has_no_switch
    refute_includes Plastic::Graph::MigrationList::HELD.keys, INPUTS
  end

  def test_the_migration_drops_the_column_and_leaves_the_layout_of_a_new_store
    home = previous_home
    before = columns(home)
    migrate_store(home)

    assert_equal [true, fresh_columns], [before.include?("input"), columns(home)]
  end

  def test_the_migration_copies_each_stored_input_as_position_1
    home = seeded
    migrate_store(home)

    assert_equal [["1", "n1", 1, "docs/a.md", "o"]], inputs(home)
  end

  def test_the_migration_keeps_each_node_row
    home = seeded
    migrate_store(home)

    assert_equal [%w[n1 n2 n3], true], [alpha_rows(home, "work_graph.db", "SELECT id FROM nodes ORDER BY id").flatten, recorded(home).include?(INPUTS)]
  end

  def migrated_with_second_path
    seeded.tap do |home|
      migrate_store(home)
      SQLite3::Database.open(alpha_file(home, "work_graph.db")) { |database| database.execute("INSERT INTO node_inputs VALUES ('1', 'n1', 2, 'docs/b.md', 'o')") }
    end
  end

  def test_a_down_puts_the_first_path_back_in_the_column
    home = migrated_with_second_path
    down(home)

    assert_equal [["n1", "docs/a.md"], ["n2", nil]], alpha_rows(home, "work_graph.db", "SELECT id, input FROM nodes WHERE id IN ('n1', 'n2') ORDER BY id")
  end

  def test_a_down_drops_the_table_and_removes_the_version
    home = migrated_with_second_path
    undone = down(home)

    assert_equal [INPUTS, [], false], [undone.version, columns(home, "node_inputs"), recorded(home).include?(INPUTS)]
  end

  def test_a_down_and_an_update_give_back_the_migrated_store
    home = seeded.tap { |seeded_home| migrate_store(seeded_home) }
    before = [alpha_rows(home, "work_graph.db", "SELECT * FROM nodes ORDER BY id"), inputs(home)]
    down(home)
    migrate_store(home)

    assert_equal [fresh_columns, before], [columns(home), [alpha_rows(home, "work_graph.db", "SELECT * FROM nodes ORDER BY id"), inputs(home)]]
  end
end
