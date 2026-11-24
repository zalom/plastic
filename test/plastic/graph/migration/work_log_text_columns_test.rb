# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../test_helpers/previous_store"

# Migration 20261124210000 adds the nullable columns old_text and new_text to the work log, and its down drops them again.
class GraphWorkLogTextColumnsTest < Plastic::TestCase
  include BackupHomes
  include PreviousStore

  NOW = Time.utc(2026, 11, 24, 21, 30, 0)
  VERSION = "20261124210000"
  COLUMNS = %w[old_text new_text].freeze
  ROW = "INSERT INTO work_log (intent_id, position, at, phase, node, session_id, kind, path, sha256, text, origin_id) " \
        "VALUES ('1', 1, 'then', '', '', 's-1', 'noted', '', '', 'a line', 'o')"

  def columns(home) = alpha_rows(home, "work_graph.db", "SELECT name FROM pragma_table_info('work_log')").flatten

  def seeded
    previous_home.tap { |home| SQLite3::Database.open(alpha_file(home, "work_graph.db")) { |database| database.execute(ROW) } }
  end

  def down(home) = Plastic::Graph::MigrationDown.new(home, "alpha", NOW).call

  def fresh_columns
    home = fresh_home
    Plastic::Graph::Database::ConnectionPool.release(home)
    columns(home)
  end

  def test_a_new_store_has_the_old_and_the_new_text_on_a_work_log_line
    assert_equal COLUMNS, fresh_columns & COLUMNS
  end

  def test_the_migration_has_no_switch
    refute_includes Plastic::Graph::MigrationList::HELD.keys, VERSION
  end

  def test_the_migration_adds_the_columns_and_leaves_the_layout_of_a_new_store
    home = previous_home
    before = columns(home)
    migrate_store(home)

    assert_equal [[], fresh_columns], [before & COLUMNS, columns(home)]
  end

  def test_the_migration_keeps_each_line_with_no_old_and_new_text
    home = seeded
    migrate_store(home)

    assert_equal [[["a line", nil, nil]], true],
      [alpha_rows(home, "work_graph.db", "SELECT text, old_text, new_text FROM work_log"), recorded(home).include?(VERSION)]
  end

  def test_a_down_drops_the_columns_and_removes_the_version
    home = seeded.tap { |seeded_home| migrate_store(seeded_home) }
    undone = down(home)

    assert_equal [VERSION, {}, [], false], [undone.version, undone.moved, columns(home) & COLUMNS, recorded(home).include?(VERSION)]
  end

  def test_a_down_and_an_update_give_back_the_migrated_store
    home = seeded.tap { |seeded_home| migrate_store(seeded_home) }
    before = alpha_rows(home, "work_graph.db", "SELECT * FROM work_log")
    down(home)
    migrate_store(home)

    assert_equal [fresh_columns, before], [columns(home), alpha_rows(home, "work_graph.db", "SELECT * FROM work_log")]
  end
end
