# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/migration/migration_down"
require_relative "../../../../lib/plastic/graph/migration/migration_purge"

class GraphLegacyTrimTest < Plastic::TestCase
  include PreviousStore

  NOW = Time.utc(2026, 11, 19, 13, 0, 0)
  REVISIONS = "SELECT sha256 FROM document_revisions_#{PreviousStore::DROP} ORDER BY sha256".freeze

  # Runs every migration but the page migration, which came after the trim.
  def migrate(home) = migrate_without(home, [PAGES])

  def contents(home) = legacy_tables(home).to_h { |table| [table, alpha_rows(home, "legacy.db", "SELECT * FROM \"#{table}\"").sort_by(&:inspect)] }

  def kept_revisions(home) = alpha_rows(home, "legacy.db", REVISIONS).flatten

  # A store of the previous release with a current revision beside the earlier one, and a revision of a path the sync never reads.
  def previous_home_with_revisions
    previous_home.tap do |home|
      SQLite3::Database.open(alpha_file(home, "knowledge_graph.db")) do |database|
        database.execute("INSERT INTO document_revisions VALUES ('cur', '1', 'intent.md', 'new text', 'now', 'origin')")
        database.execute("INSERT INTO document_revisions VALUES ('tmp', '1', 'resources/tmp/x.md', 'scratch', 'now', 'origin')")
        database.execute("INSERT INTO documents (intent_id, path, body, updated_at, origin_id) VALUES ('1', 'intent.md', 'new text', 'now', 'origin')")
        database.execute("INSERT INTO document_heads (intent_id, path, sha256, updated_at, origin_id) VALUES ('1', 'intent.md', 'cur', 'now', 'origin')")
      end
    end
  end

  KEPT = <<~SQL
    CREATE TABLE document_revisions_#{PreviousStore::DROP}("sha256" TEXT NOT NULL, "intent_id" TEXT NOT NULL, "path" TEXT NOT NULL, "body" TEXT NOT NULL, "created_at" TEXT NOT NULL, "origin_id" TEXT NOT NULL, UNIQUE("sha256", "intent_id", "path", "origin_id"));
    INSERT INTO document_revisions_#{PreviousStore::DROP} VALUES ('sha', '1', 'intent.md', 'old text', 'then', 'origin');
    INSERT INTO document_revisions_#{PreviousStore::DROP} VALUES ('cur', '1', 'intent.md', 'new text', 'now', 'origin');
    INSERT INTO document_revisions_#{PreviousStore::DROP} VALUES ('tmp', '1', 'resources/tmp/x.md', 'scratch', 'now', 'origin');
  SQL

  # A store that ran the drop as release 3.0.0-beta.4 shipped it, before the trim: its legacy.db holds the copy the drop kept then, and a current revision beside the earlier one. The cleanup that deletes the copy has run before the copy is put there, so the trim runs alone.
  def dropped_home
    previous_home.tap do |home|
      migrate_without(home, [TRIM, PAGES])
      SQLite3::Database.open(alpha_file(home, "legacy.db")) { |database| database.execute_batch(KEPT) }
      SQLite3::Database.open(alpha_file(home, "knowledge_graph.db")) do |database|
        database.execute("INSERT INTO documents (intent_id, path, body, updated_at, origin_id) VALUES ('1', 'intent.md', 'new text', 'now', 'origin')")
        database.execute("INSERT INTO document_heads (intent_id, path, sha256, updated_at, origin_id) VALUES ('1', 'intent.md', 'cur', 'now', 'origin')")
      end
    end
  end

  def test_the_trim_leaves_only_the_earlier_texts_of_read_paths_and_no_sqlar_row
    home = dropped_home
    migrate(home)

    assert_equal [["document_revisions_#{DROP}"], %w[sha], true], [legacy_tables(home), kept_revisions(home), recorded(home).include?(TRIM)]
  end

  def test_the_trim_names_what_it_removed_from_legacy_db
    home = dropped_home

    assert_includes migrate(home).notes, "migrate: alpha trimmed 3 rows from legacy.db that a down rebuilds or that no sync reads"
  end

  def test_a_store_that_runs_the_trim_and_the_cleanup_in_one_run_keeps_no_copy_of_the_revisions
    home = dropped_home
    SQLite3::Database.open(alpha_file(home, "knowledge_graph.db")) { |database| database.execute("DELETE FROM schema_migrations WHERE version = ?", [MISTAKES]) }
    migrate(home)

    assert_equal [[], true, true], [legacy_tables(home), recorded(home).include?(TRIM), recorded(home).include?(MISTAKES)]
  end

  def test_the_trim_goes_down_by_removing_its_version_alone
    home = utc_down(dropped_home.tap { |dropped| migrate_store(dropped) })
    Plastic::Graph::MigrationDown.new(home, "alpha", NOW).call
    before = contents(home)
    undone = Plastic::Graph::MigrationDown.new(home, "alpha", NOW).call

    assert_equal [TRIM, {}, false, before], [undone.version, undone.moved, recorded(home).include?(TRIM), contents(home)]
  end
end
