# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../test_helpers/previous_store"

# The ten tables as the old checkout made them, and a live row in each knowledge table that shares a name.
module LeftoverTexts
  TABLES = %w[savepoints changes intents clusters completions approvals verdicts archives archive_entries printed].freeze
  EXACT = [
    'CREATE TABLE "savepoints"("intent_id" TEXT NOT NULL, "position" INTEGER NOT NULL, "at" TEXT, "text" TEXT NOT NULL, "origin_id" TEXT NOT NULL, "session_id" TEXT, UNIQUE("intent_id", "position", "origin_id"))',
    'CREATE TABLE "changes"("seq" INTEGER PRIMARY KEY AUTOINCREMENT, "table" TEXT NOT NULL, "key" TEXT NOT NULL, "operation" TEXT NOT NULL CHECK(operation IN (\'put\', \'remove\')), "row" TEXT, "at" TEXT NOT NULL, "origin_id" TEXT NOT NULL)',
    'CREATE TABLE "intents"("id" INTEGER PRIMARY KEY AUTOINCREMENT, "intent_id" TEXT NOT NULL, "parent_id" TEXT, "ref" TEXT, "origin_id" TEXT NOT NULL, "slug" TEXT NOT NULL, "title" TEXT NOT NULL, "kind" TEXT, "status" TEXT NOT NULL CHECK(status IN (\'open\', \'active\', \'parked\', \'future\', \'done\', \'abandoned\')), "disposition" TEXT, "opened_at" TEXT, "closed_at" TEXT, "updated_at" TEXT, UNIQUE("intent_id", "origin_id"))',
    'CREATE TABLE "clusters"("name" TEXT NOT NULL, "intent_id" TEXT NOT NULL, "origin_id" TEXT NOT NULL, UNIQUE("name", "intent_id", "origin_id"))',
    'CREATE TABLE "completions"("intent_id" TEXT NOT NULL, "origin_id" TEXT NOT NULL, "at" TEXT NOT NULL, "session_id" TEXT NOT NULL, "judge" TEXT NOT NULL, "criteria" TEXT NOT NULL, "evidence" TEXT NOT NULL, "outcome_sha256" TEXT NOT NULL, UNIQUE("intent_id", "origin_id"))',
    'CREATE TABLE "approvals"("intent_id" TEXT NOT NULL, "origin_id" TEXT NOT NULL, "at" TEXT, "session_id" TEXT, UNIQUE("intent_id", "origin_id"))',
    'CREATE TABLE "verdicts"("intent_id" TEXT NOT NULL, "round" INTEGER NOT NULL, "origin_id" TEXT NOT NULL, "verdict" TEXT NOT NULL, "findings" TEXT NOT NULL, "at" TEXT, "session_id" TEXT, UNIQUE("intent_id", "round", "origin_id"))',
    'CREATE TABLE "archives"("intent_id" TEXT NOT NULL, "at" TEXT, "origin_id" TEXT NOT NULL, "restored_at" TEXT, "session_id" TEXT, UNIQUE("intent_id", "origin_id"))',
    'CREATE TABLE "archive_entries"("intent_id" TEXT NOT NULL, "path" TEXT NOT NULL, "origin_id" TEXT NOT NULL, "kind" TEXT NOT NULL, "mode" INTEGER, "mtime" TEXT, "data" BLOB, UNIQUE("intent_id", "path", "origin_id"))',
    'CREATE TABLE "printed"("path" TEXT NOT NULL, "sha256" TEXT NOT NULL, "at" TEXT NOT NULL, "origin_id" TEXT NOT NULL, UNIQUE("path"))'
  ].freeze
  DDL = EXACT.map { |sql| sql.sub("CREATE TABLE", "CREATE TABLE IF NOT EXISTS") }.join(";\n")
  LIVE_ROWS = <<~SQL
    INSERT INTO main.intents (intent_id, origin_id, slug, title, status) VALUES ('live-1', 'o', 'live', 'Live intent', 'open');
    INSERT INTO main.printed (path, sha256, at, origin_id) VALUES ('live/spec.md', 'sha', 'then', 'o');
  SQL
end

# Migration 20261124120000 drops the ten tables of older layouts that the work database no longer declares, keeps their
# rows when one holds any, never touches the live tables of the same names in knowledge_graph.db and plastic.db, and its
# down builds them again in the old shape.
class GraphLeftoverWorkTablesTest < Plastic::TestCase
  include BackupHomes
  include PreviousStore
  include LeftoverTexts

  NOW = Time.utc(2026, 11, 24, 12, 0, 0)
  def work_tables(home) = alpha_rows(home, "work_graph.db", "SELECT name FROM sqlite_master WHERE type = 'table'").flatten

  def table_texts(home) = alpha_rows(home, "work_graph.db", "SELECT sql FROM sqlite_master WHERE name IN ('#{TABLES.join("', '")}')").flatten

  def work_count(home, table) = alpha_rows(home, "work_graph.db", "SELECT count(*) FROM \"#{table}\"").first.first

  def kept(home) = legacy_tables(home).select { |name| name.end_with?(LEFTOVERS) }

  # The store of the migrated release after a checkout from before the schema gate opened it: the ten tables are in
  # work_graph.db with no row, and the live intents and printed tables of knowledge_graph.db hold a row each.
  def remade
    migrated_previous_home.tap do |home|
      SQLite3::Database.open(alpha_file(home, "work_graph.db")) { |database| database.execute_batch(DDL) }
      SQLite3::Database.open(alpha_file(home, "knowledge_graph.db")) do |database|
        database.execute("DELETE FROM schema_migrations WHERE version = ?", [LEFTOVERS])
        database.execute_batch(LIVE_ROWS)
      end
      forget(home)
    end
  end

  def holding_a_row
    remade.tap do |home|
      SQLite3::Database.open(alpha_file(home, "work_graph.db")) { |database| database.execute("INSERT INTO savepoints VALUES ('1', 1, 'then', 'saved', 'o', 's')") }
    end
  end

  # The mistaken rows cleanup is the newest and removes its version alone, so its down comes first.
  def down(home) = 5.times.map { Plastic::Graph::MigrationDown.new(home, "alpha", NOW).call }.last

  def test_a_new_store_has_none_of_the_ten_tables_in_the_work_database
    home = fresh_home
    Plastic::Graph::Database::ConnectionPool.release(home)

    assert_empty work_tables(home) & TABLES
  end

  def test_the_migration_has_no_switch
    refute_includes Plastic::Graph::MigrationList::HELD.keys, LEFTOVERS
  end

  def test_a_store_with_the_ten_empty_tables_migrates_to_none_and_records_the_version
    home = remade
    migrate_store(home)

    assert_equal [[], true], [work_tables(home) & TABLES, recorded(home).include?(LEFTOVERS)]
  end

  def test_a_run_that_drops_only_empty_tables_keeps_nothing_in_legacy_db
    home = remade
    migrate_store(home)

    assert_empty kept(home)
  end

  def test_the_live_intents_and_printed_tables_keep_every_row_and_never_reach_legacy_db
    home = remade
    migrate_store(home)

    assert_equal [[["live-1"]], [["live/spec.md"]], []],
      [alpha_rows(home, "knowledge_graph.db", "SELECT intent_id FROM intents"), alpha_rows(home, "knowledge_graph.db", "SELECT path FROM printed"), kept(home)]
  end

  def test_the_live_tables_keep_their_rows_when_a_work_table_of_the_same_name_holds_one_too
    home = holding_a_row
    SQLite3::Database.open(alpha_file(home, "work_graph.db")) { |database| database.execute("INSERT INTO printed VALUES ('old.md', 'sha', 'then', 'o')") }
    migrate_store(home)

    assert_equal [[["live-1"]], [["live/spec.md"]], ["printed_#{LEFTOVERS}", "savepoints_#{LEFTOVERS}"]],
      [alpha_rows(home, "knowledge_graph.db", "SELECT intent_id FROM intents"), alpha_rows(home, "knowledge_graph.db", "SELECT path FROM printed"), kept(home)]
  end

  def test_a_store_that_never_had_the_tables_only_records_the_version
    home = migrated_previous_home
    SQLite3::Database.open(alpha_file(home, "knowledge_graph.db")) { |database| database.execute("DELETE FROM schema_migrations WHERE version = ?", [LEFTOVERS]) }
    forget(home)
    migrate_store(home)

    assert_equal [[], true], [work_tables(home) & TABLES, recorded(home).include?(LEFTOVERS)]
  end

  def test_a_table_that_holds_a_row_is_dropped_only_after_its_row_is_kept_whole_in_legacy_db
    home = holding_a_row
    migrate_store(home)

    assert_equal [[], [["1", 1, "then", "saved", "o", "s"]], ["savepoints_#{LEFTOVERS}"]],
      [work_tables(home) & TABLES, alpha_rows(home, "legacy.db", "SELECT * FROM savepoints_#{LEFTOVERS}"), kept(home)]
  end

  def test_a_down_builds_the_ten_tables_again_with_the_text_of_the_old_tables
    home = remade
    migrate_store(home)
    undone = down(home)

    assert_equal [LEFTOVERS, EXACT.sort], [undone.version, table_texts(home).sort]
  end

  def test_a_down_removes_the_version_and_leaves_the_tables_empty
    home = remade
    migrate_store(home)
    undone = down(home)

    assert_equal [LEFTOVERS, false, [0] * 10], [undone.version, recorded(home).include?(LEFTOVERS), TABLES.map { |table| work_count(home, table) }]
  end

  def test_a_down_puts_back_the_row_that_the_migration_kept
    home = holding_a_row
    migrate_store(home)
    undone = down(home)

    assert_equal [LEFTOVERS, [["saved"]], []], [undone.version, alpha_rows(home, "work_graph.db", "SELECT text FROM savepoints"), kept(home)]
  end

  def test_a_down_leaves_the_live_tables_alone
    home = remade
    migrate_store(home)
    down(home)

    assert_equal [[["live-1"]], [["live/spec.md"]]],
      [alpha_rows(home, "knowledge_graph.db", "SELECT intent_id FROM intents"), alpha_rows(home, "knowledge_graph.db", "SELECT path FROM printed")]
  end

  def test_a_down_and_an_update_give_back_the_migrated_store
    home = remade
    migrate_store(home)
    down(home)
    migrate_store(home)

    assert_equal [[], true], [work_tables(home) & TABLES, recorded(home).include?(LEFTOVERS)]
  end
end
