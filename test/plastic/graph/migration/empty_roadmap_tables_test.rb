# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../test_helpers/previous_store"

# Migration 20261124090000 drops the five roadmap tables that a checkout from before the schema gate made again on a
# migrated store, keeps their rows when one holds any, and its down builds them again in the old shape.
class GraphEmptyRoadmapTablesTest < Plastic::TestCase
  include BackupHomes
  include PreviousStore

  EMPTY = "20261124090000"
  NOW = Time.utc(2026, 11, 24, 9, 0, 0)
  TABLES = %w[roadmaps batches roadmap_items roadmap_edges roadmap_log].freeze
  # Each table as the live tables and the legacy.db copies of migration 20261123120000 hold it: their text in sqlite_master,
  # with UNIQUE keys and the batch and position of an item NOT NULL.
  EXACT = [
    'CREATE TABLE "roadmaps"("slug" TEXT NOT NULL, "title" TEXT NOT NULL, "goal" TEXT, "opened_at" TEXT, "updated_at" TEXT, "origin_id" TEXT NOT NULL, UNIQUE("slug", "origin_id"))',
    'CREATE TABLE "batches"("roadmap" TEXT NOT NULL, "position" INTEGER NOT NULL, "title" TEXT NOT NULL, "goal" TEXT, "done" TEXT, "updated_at" TEXT, "origin_id" TEXT NOT NULL, UNIQUE("roadmap", "position", "origin_id"))',
    'CREATE TABLE "roadmap_items"("roadmap" TEXT NOT NULL, "item" TEXT NOT NULL, "batch" INTEGER NOT NULL, "position" INTEGER NOT NULL, "title" TEXT, "goal" TEXT, "done" TEXT, "intent_id" TEXT, "mark" TEXT, "updated_at" TEXT, "origin_id" TEXT NOT NULL, UNIQUE("roadmap", "item", "origin_id"))',
    'CREATE TABLE "roadmap_edges"("roadmap" TEXT NOT NULL, "from" TEXT NOT NULL, "to" TEXT NOT NULL, "kind" TEXT NOT NULL, "origin_id" TEXT NOT NULL, UNIQUE("roadmap", "from", "to", "origin_id"))',
    'CREATE TABLE "roadmap_log"("roadmap" TEXT NOT NULL, "position" INTEGER NOT NULL, "at" TEXT, "text" TEXT NOT NULL, "session_id" TEXT, "origin_id" TEXT NOT NULL, UNIQUE("roadmap", "position", "origin_id"))'
  ].freeze
  DDL = EXACT.map { |sql| sql.sub("CREATE TABLE", "CREATE TABLE IF NOT EXISTS") }.join(";\n")

  def work_tables(home) = alpha_rows(home, "work_graph.db", "SELECT name FROM sqlite_master WHERE type = 'table'").flatten

  def table_texts(home) = alpha_rows(home, "work_graph.db", "SELECT sql FROM sqlite_master WHERE name IN ('#{TABLES.join("', '")}')").flatten

  # The store of the migrated release after a checkout from before the schema gate opened it: the five tables are back, with no row.
  def remade
    migrated_previous_home.tap do |home|
      SQLite3::Database.open(alpha_file(home, "work_graph.db")) { |database| database.execute_batch(DDL) }
      SQLite3::Database.open(alpha_file(home, "knowledge_graph.db")) { |database| database.execute("DELETE FROM schema_migrations WHERE version = ?", [EMPTY]) }
      forget(home)
    end
  end

  def holding_a_row
    remade.tap do |home|
      SQLite3::Database.open(alpha_file(home, "work_graph.db")) { |database| database.execute("INSERT INTO roadmaps VALUES ('plan', 'Plan', 'g', 'then', 'then', 'o')") }
    end
  end

  # The mistaken rows cleanup and the leftover work tables migration are the newest and remove their versions alone, so their downs come first.
  def down(home) = 7.times.map { Plastic::Graph::MigrationDown.new(home, "alpha", NOW).call }.last

  def test_a_new_store_has_no_roadmap_table
    home = fresh_home
    Plastic::Graph::Database::ConnectionPool.release(home)

    assert_empty work_tables(home) & TABLES
  end

  def test_an_old_store_with_the_five_empty_tables_migrates_to_none
    home = remade
    migrate_store(home)

    assert_equal [[], true], [work_tables(home) & TABLES, recorded(home).include?(EMPTY)]
  end

  def test_a_run_that_drops_only_empty_tables_keeps_nothing_in_legacy_db
    home = remade
    migrate_store(home)

    assert_includes recorded(home), EMPTY

    assert_empty legacy_tables(home).select { |name| name.end_with?(EMPTY) }
  end

  def test_a_store_that_never_had_the_tables_only_records_the_version
    home = migrated_previous_home
    SQLite3::Database.open(alpha_file(home, "knowledge_graph.db")) { |database| database.execute("DELETE FROM schema_migrations WHERE version = ?", [EMPTY]) }
    forget(home)
    migrate_store(home)

    assert_equal [[], true], [work_tables(home) & TABLES, recorded(home).include?(EMPTY)]
  end

  def test_a_table_that_holds_a_row_is_dropped_only_after_its_row_is_kept_in_legacy_db
    home = holding_a_row
    migrate_store(home)

    assert_equal [[], 1, ["roadmaps_#{EMPTY}"]], [work_tables(home) & TABLES, alpha_rows(home, "legacy.db", "SELECT count(*) FROM roadmaps_#{EMPTY}").first.first, legacy_tables(home).select { |name| name.end_with?(EMPTY) }]
  end

  def test_a_down_builds_the_five_tables_again_with_the_text_of_the_old_tables
    home = remade
    migrate_store(home)
    undone = down(home)

    assert_equal [EMPTY, EXACT.sort], [undone.version, table_texts(home).sort]
  end

  def test_a_down_removes_the_version_and_leaves_the_tables_empty
    home = remade
    migrate_store(home)
    undone = down(home)

    assert_equal [EMPTY, false, [0] * 5], [undone.version, recorded(home).include?(EMPTY), TABLES.map { |table| alpha_rows(home, "work_graph.db", "SELECT count(*) FROM #{table}").first.first }]
  end

  def test_a_down_puts_back_the_row_that_the_migration_kept
    home = holding_a_row
    migrate_store(home)
    undone = down(home)

    assert_equal [EMPTY, [["plan"]]], [undone.version, alpha_rows(home, "work_graph.db", "SELECT slug FROM roadmaps")]
  end

  def test_a_down_and_an_update_give_back_the_migrated_store
    home = remade
    migrate_store(home)
    down(home)
    migrate_store(home)

    assert_equal [[], true], [work_tables(home) & TABLES, recorded(home).include?(EMPTY)]
  end
end
