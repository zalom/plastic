# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../test_helpers/previous_store"
require_relative "../../../../lib/plastic/graph/migration/migration_down"
require_relative "../../../../lib/plastic/commands/store/migration/down"

# The previous release's store, with the roadmap tables filled, for the tests of the migration and its down.
module RoadmapStoreHelpers
  include PreviousStore

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
    open_intents(home)
    SQLite3::Database.open(alpha_file(home, "work_graph.db")) { |database| database.execute_batch(DDL) }
    home
  end

  # The three intents the roadmap items opened.
  def open_intents(home)
    SQLite3::Database.open(alpha_file(home, "knowledge_graph.db")) do |database|
      (1..3).each { |id| database.execute("INSERT INTO intents (intent_id, origin_id, slug, title, status) VALUES (?, 'o', ?, ?, 'open')", [id.to_s, "intent-#{id}", "Intent #{id}"]) }
    end
  end

  def needs(home) = alpha_rows(home, "knowledge_graph.db", "SELECT from_ref, to_ref FROM links WHERE kind = 'needs' ORDER BY from_ref, to_ref")

  def work_tables(home) = alpha_rows(home, "work_graph.db", "SELECT name FROM sqlite_master WHERE type = 'table'").flatten

  def count(home, file, table) = alpha_rows(home, file, "SELECT count(*) FROM #{table}").first.first

  # A second roadmap whose one edge joins the intents the first roadmap already joins.
  def copy_roadmap(home)
    SQLite3::Database.open(alpha_file(home, "work_graph.db")) do |database|
      database.execute_batch(<<~SQL)
        INSERT INTO roadmaps VALUES ('copy', 'Copy', 'g', 'then', 'then', 'o');
        INSERT INTO roadmap_items VALUES ('copy', 'a', 1, 1, 'A', NULL, NULL, '1', NULL, 'then', 'o');
        INSERT INTO roadmap_items VALUES ('copy', 'b', 1, 2, 'B', NULL, NULL, '2', NULL, 'then', 'o');
        INSERT INTO roadmap_edges VALUES ('copy', 'a', 'b', 'after', 'o');
      SQL
    end
  end
end

# The migration that turns each roadmap's item order into needs links between the intents the items opened, then
# drops the roadmap tables and keeps their rows in legacy.db.
class RoadmapNeedsMigrationTest < Plastic::TestCase
  include RoadmapStoreHelpers

  def test_each_roadmap_edge_becomes_a_needs_link_from_the_later_intent_to_the_earlier_one
    home = roadmap_home
    migrate_store(home)

    assert_equal [%w[2 1], %w[3 2]], needs(home)
  end

  def test_an_edge_between_two_items_of_one_intent_is_skipped_and_counted
    home = roadmap_home
    report = migrate_store(home)

    assert_match(/skipped 1 roadmap edge\b/, report.notes.join("\n"))
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

  def test_two_roadmaps_that_hold_the_same_intent_pair_write_one_link_and_skip_the_other
    home = roadmap_home
    copy_roadmap(home)
    report = migrate_store(home)

    assert_equal [%w[2 1], %w[3 2]], needs(home)
    assert_match(/wrote 2 needs links.*skipped 2 roadmap edges/, report.notes.join("\n"))
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
    assert_match(/skipped 2 roadmap edges/, report.notes.join("\n"))
  end
end

# The down of the migration puts the roadmap rows back and takes off only the needs links the migration wrote.
class RoadmapNeedsDownTest < Plastic::TestCase
  include RoadmapStoreHelpers

  # The empty roadmap tables, node inputs, deadline and driver migrations are the newest, so their downs come first and the next down undoes the roadmap migration.
  def undo_drivers(home) = 8.times { Plastic::Graph::MigrationDown.new(home, "alpha", MIGRATED_AT).call }

  def down_result(home) = plastic("store", "migration", "down", "--project", "alpha", env: { "PLASTIC_HOME" => home }, table: Plastic::CLI::TABLE, clock: FixedClock::Clock.new(MIGRATED_AT + 3600))

  def test_a_down_puts_the_roadmap_rows_back_and_removes_the_needs_links
    home = roadmap_home
    migrate_store(home)
    undo_drivers(home)
    Plastic::Graph::MigrationDown.new(home, "alpha", MIGRATED_AT).call

    assert_equal [[], 4, 3], [needs(home), count(home, "work_graph.db", "roadmap_items"), count(home, "work_graph.db", "roadmap_edges")]
  end

  def test_a_down_removes_only_the_needs_links_the_migration_wrote
    home = roadmap_home
    migrate_store(home)
    undo_drivers(home)
    SQLite3::Database.open(alpha_file(home, "knowledge_graph.db")) { |database| database.execute("INSERT INTO links (from_ref, to_ref, kind, at, origin_id) VALUES ('3', '1', 'needs', '2026-11-23T00:00:00Z', 'o')") }
    Plastic::Graph::MigrationDown.new(home, "alpha", MIGRATED_AT).call

    assert_equal [%w[3 1]], needs(home)
  end

  def test_a_down_says_how_many_needs_links_it_removed
    home = roadmap_home
    migrate_store(home)
    undo_drivers(home)
    undone = Plastic::Graph::MigrationDown.new(home, "alpha", MIGRATED_AT).call

    assert_equal [2, {}], [undone.removed, undone.built]
  end

  def test_the_down_workflow_of_a_version_that_removes_no_links_prints_no_removed_line
    result = down_result(migrated_to_owner)

    refute_match(/removed/, result.out)
  end

  def test_the_down_workflow_names_one_removed_link_in_the_singular
    home = roadmap_home
    SQLite3::Database.open(alpha_file(home, "work_graph.db")) { |database| database.execute("DELETE FROM roadmap_edges WHERE \"from\" = 'b'") }
    migrate_store(home)
    undo_drivers(home)

    assert_includes down_result(home).out, "down: removed 1 needs link that the migration wrote"
  end

  def test_the_down_workflow_prints_removed_and_not_built_links
    home = roadmap_home
    migrate_store(home)
    undo_drivers(home)
    result = down_result(home)

    assert_includes result.out, "down: removed 2 needs links that the migration wrote"
    refute_match(/built 2/, result.out)
  end
end

# The migrate line of one store: what was written and what was skipped.
class RoadmapNeedsResultTest < Minitest::Test
  Result = Plastic::Graph::RoadmapNeeds::Result

  def test_a_store_with_nothing_to_write_or_skip_has_no_line
    assert_nil Result.new(written: 0, skipped: 0).line("alpha")
  end

  def test_one_written_link_is_named_in_the_singular
    assert_equal "migrate: alpha wrote 1 needs link from the roadmap edges", Result.new(written: 1, skipped: 0).line("alpha")
  end

  def test_one_skipped_edge_is_named_in_the_singular_after_the_links
    assert_match(/wrote 2 needs links from the roadmap edges and skipped 1 roadmap edge that cannot be a link/, Result.new(written: 2, skipped: 1).line("alpha"))
  end
end
