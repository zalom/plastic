# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../test_helpers/previous_store"
require_relative "../../../../lib/plastic/graph/migration/migration_down"

# The migration that turns each roadmap's item order into needs links between the intents the items opened, then
# drops the roadmap tables and keeps their rows in legacy.db.
class RoadmapNeedsMigrationTest < Plastic::TestCase
  include PreviousStore

  NEEDS = "20261123120000"
  TABLES = %w[roadmaps batches roadmap_items roadmap_edges roadmap_log].freeze
  DDL = <<~SQL
    CREATE TABLE IF NOT EXISTS "roadmaps" ("slug" TEXT NOT NULL, "title" TEXT NOT NULL, "goal" TEXT, "opened_at" TEXT, "updated_at" TEXT, "origin_id" TEXT NOT NULL, PRIMARY KEY ("slug", "origin_id"));
    CREATE TABLE IF NOT EXISTS "batches" ("roadmap" TEXT NOT NULL, "position" INTEGER NOT NULL, "title" TEXT NOT NULL, "goal" TEXT, "done" TEXT, "updated_at" TEXT, "origin_id" TEXT NOT NULL, PRIMARY KEY ("roadmap", "position", "origin_id"));
    CREATE TABLE IF NOT EXISTS "roadmap_items" ("roadmap" TEXT NOT NULL, "item" TEXT NOT NULL, "batch" INTEGER, "position" INTEGER, "title" TEXT, "goal" TEXT, "done" TEXT, "intent_id" TEXT, "mark" TEXT, "updated_at" TEXT, "origin_id" TEXT NOT NULL, PRIMARY KEY ("roadmap", "item", "origin_id"));
    CREATE TABLE IF NOT EXISTS "roadmap_edges" ("roadmap" TEXT NOT NULL, "from" TEXT NOT NULL, "to" TEXT NOT NULL, "kind" TEXT NOT NULL, "origin_id" TEXT NOT NULL, PRIMARY KEY ("roadmap", "from", "to", "origin_id"));
    CREATE TABLE IF NOT EXISTS "roadmap_log" ("roadmap" TEXT NOT NULL, "position" INTEGER NOT NULL, "at" TEXT, "text" TEXT NOT NULL, "session_id" TEXT, "origin_id" TEXT NOT NULL, PRIMARY KEY ("roadmap", "position", "origin_id"));
    INSERT INTO roadmaps VALUES ('plan', 'Plan', 'g', 'then', 'then', 'o');
    INSERT INTO batches VALUES ('plan', 1, 'One', 'g', 'd', 'then', 'o');
    INSERT INTO roadmap_items VALUES ('plan', 'a', 1, 1, 'A', NULL, NULL, '1', NULL, 'then', 'o');
    INSERT INTO roadmap_items VALUES ('plan', 'b', 1, 2, 'B', NULL, NULL, '2', NULL, 'then', 'o');
    INSERT INTO roadmap_items VALUES ('plan', 'c', 1, 3, 'C', NULL, NULL, '3', NULL, 'then', 'o');
    INSERT INTO roadmap_items VALUES ('plan', 'd', 1, 4, 'D', NULL, NULL, '3', NULL, 'then', 'o');
    INSERT INTO roadmap_edges VALUES ('plan', 'a', 'b', 'after', 'o');
    INSERT INTO roadmap_edges VALUES ('plan', 'b', 'c', 'after', 'o');
    INSERT INTO roadmap_edges VALUES ('plan', 'c', 'd', 'after', 'o');
    INSERT INTO roadmap_log VALUES ('plan', 1, 'then', 'opened', 's1', 'o');
  SQL

  # The previous release's store: the roadmap tables hold rows and the newest migration is not recorded.
  def roadmap_home
    home = previous_home
    SQLite3::Database.open(alpha_file(home, "work_graph.db")) { |database| database.execute_batch(DDL) }
    SQLite3::Database.open(alpha_file(home, "knowledge_graph.db")) { |database| database.execute("DELETE FROM schema_migrations WHERE version = ?", [NEEDS]) }
    home
  end

  def needs(home) = alpha_rows(home, "knowledge_graph.db", "SELECT from_ref, to_ref FROM links WHERE kind = 'needs' ORDER BY from_ref, to_ref")

  def work_tables(home) = alpha_rows(home, "work_graph.db", "SELECT name FROM sqlite_master WHERE type = 'table'").flatten

  def count(home, file, table) = alpha_rows(home, file, "SELECT count(*) FROM #{table}").first.first

  def test_each_roadmap_edge_becomes_a_needs_link_from_the_later_intent_to_the_earlier_one
    home = roadmap_home
    migrate_store(home)

    assert_equal [%w[2 1], %w[3 2]], needs(home)
  end

  def test_an_edge_between_two_items_of_one_intent_is_skipped_and_counted
    home = roadmap_home
    report = migrate_store(home)

    assert(report.notes.any? { |note| note.match?(/1 roadmap edge.*skipped/) }, report.notes.inspect)
  end

  def test_the_five_roadmap_tables_are_dropped_from_the_work_file
    home = roadmap_home
    migrate_store(home)

    assert_empty work_tables(home) & TABLES
  end

  def test_the_roadmap_rows_stay_in_legacy_db_under_the_version
    home = roadmap_home
    migrate_store(home)

    assert_equal [4, 3, 1], %w[roadmap_items roadmap_edges roadmap_log].map { |table| count(home, "legacy.db", "#{table}_#{NEEDS}") }
  end

  def test_the_migration_is_recorded
    home = roadmap_home
    migrate_store(home)

    assert_includes recorded(home), NEEDS
  end

  def test_a_down_puts_the_roadmap_rows_back_and_removes_the_needs_links
    home = roadmap_home
    migrate_store(home)
    Plastic::Graph::MigrationDown.new(home, "alpha", MIGRATED_AT).call

    assert_equal [[], 4, 3], [needs(home), count(home, "work_graph.db", "roadmap_items"), count(home, "work_graph.db", "roadmap_edges")]
  end

  def test_a_new_store_declares_no_roadmap_table
    home = File.join(Dir.mktmpdir, ".plastic")
    Plastic::Graph.create(home:, store: "alpha")

    assert_empty work_tables(home) & TABLES
  end

  def test_an_edge_that_would_close_a_loop_is_skipped_and_counted_with_the_self_edge
    home = roadmap_home
    SQLite3::Database.open(alpha_file(home, "work_graph.db")) { |database| database.execute("INSERT INTO roadmap_edges VALUES ('plan', 'b', 'a', 'after', 'o')") }
    report = migrate_store(home)

    assert_equal [%w[2 1], %w[3 2]], needs(home)
    assert(report.notes.any? { |note| note.match?(/2 roadmap edges.*skipped/) }, report.notes.inspect)
  end
end
