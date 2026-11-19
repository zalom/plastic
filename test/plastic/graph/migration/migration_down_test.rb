# frozen_string_literal: true

require_relative "../../../test_helper"
require "digest"
require_relative "../../../../lib/plastic/graph/migration/migration_down"

class GraphMigrationDownTest < Plastic::TestCase
  include PreviousStore

  NOW = Time.utc(2026, 11, 19, 13, 0, 0)
  TABLES = "SELECT type, name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name"

  def down(home, **options) = Plastic::Graph::MigrationDown.new(home, "alpha", NOW, **options)

  def layout(home) = %w[knowledge_graph.db work_graph.db retrieval_graph.db].to_h { |name| [name, alpha_rows(home, name, TABLES)] }

  def contents(home, name) = alpha_rows(home, name, "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name").flatten.to_h { |table| [table, alpha_rows(home, name, "SELECT * FROM \"#{table}\"").sort_by(&:inspect)] }

  def test_a_store_whose_newest_migration_kept_nothing_is_refused
    assert_equal "migration #{DROP} kept nothing in legacy.db, so a down cannot undo it; restore a backup to go back",
      down(migrated_previous_home, keeps: []).refusal
  end

  def test_a_store_that_can_go_down_has_no_refusal
    assert_nil down(migrated_previous_home).refusal
  end

  def test_a_down_gives_the_store_the_layout_the_previous_release_wrote
    home = previous_home
    before = layout(home).fetch("knowledge_graph.db")
    migrate_store(home)
    down(home).call

    assert_equal before, layout(home).fetch("knowledge_graph.db")
  end

  def test_a_down_answers_the_version_and_the_rows_it_put_back_by_table
    undone = down(migrated_previous_home).call

    assert_equal [DROP, { "document_revisions" => 1, "sqlar" => 1 }], [undone.version, undone.moved]
  end

  def test_a_down_and_then_an_update_give_back_the_migrated_store_and_its_legacy_rows
    home = migrated_previous_home
    before = [layout(home), contents(home, "knowledge_graph.db"), contents(home, "legacy.db")]
    down(home).call
    migrate_store(home)

    assert_equal before, [layout(home), contents(home, "knowledge_graph.db"), contents(home, "legacy.db")]
  end
  # A document written after the migration, with its head, as the code after the drop writes it: no revision row.
  def write_document(home, intent_id, path, body, sha = Digest::SHA256.hexdigest(body))
    SQLite3::Database.open(alpha_file(home, "knowledge_graph.db")) do |database|
      database.execute("INSERT INTO documents (intent_id, path, body, updated_at, origin_id) VALUES (?, ?, ?, ?, ?)", [intent_id, path, body, "now", "origin"])
      database.execute("INSERT INTO document_heads (intent_id, path, sha256, updated_at, origin_id) VALUES (?, ?, ?, ?, ?)", [intent_id, path, sha, "now", "origin"])
    end
  end

  def revisions(home) = alpha_rows(home, "knowledge_graph.db", "SELECT * FROM document_revisions ORDER BY intent_id")

  def test_a_down_gives_each_document_written_after_the_migration_its_revision_row
    home = migrated_previous_home
    write_document(home, "2", "spec.md", "new text")
    down(home).call

    assert_equal [["sha", "1", "intent.md", "old text", "then", "origin"], [Digest::SHA256.hexdigest("new text"), "2", "spec.md", "new text", "now", "origin"]], revisions(home)
  end

  def test_a_down_adds_no_revision_row_for_a_document_whose_kept_revision_came_back
    home = migrated_previous_home
    write_document(home, "1", "intent.md", "old text", "sha")
    down(home).call

    assert_equal [["sha", "1", "intent.md", "old text", "then", "origin"]], revisions(home)
  end

  def test_a_down_answers_the_revision_rows_it_built_by_table
    home = migrated_previous_home
    write_document(home, "2", "spec.md", "new text")

    assert_equal({ "document_revisions" => 1 }, down(home).call.built)
  end
end
