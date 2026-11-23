# frozen_string_literal: true

require_relative "../../../test_helper"
require "digest"
require_relative "../../../../lib/plastic/graph/migration/migration_down"

class GraphMigrationDownTest < Plastic::TestCase
  include PreviousStore
  include Beta2Store

  NOW = Time.utc(2026, 11, 19, 13, 0, 0)
  TABLES = "SELECT type, name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name"

  def down(home, **options) = Plastic::Graph::MigrationDown.new(home, "alpha", NOW, **options)

  def layout(home) = %w[knowledge_graph.db work_graph.db retrieval_graph.db].to_h { |name| [name, alpha_rows(home, name, TABLES)] }

  def contents(home, name) = alpha_rows(home, name, "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name").flatten.to_h { |table| [table, alpha_rows(home, name, "SELECT * FROM \"#{table}\"").sort_by(&:inspect)] }

  def test_a_store_whose_newest_migration_kept_nothing_is_refused
    assert_equal "migration #{DROP} kept nothing in legacy.db, so a down cannot undo it; restore a backup to go back",
      down(migrated_to_drop, keeps: []).refusal
  end

  def test_a_store_from_before_the_baseline_is_refused_until_plastic_update_runs_it
    assert_equal "alpha has not run every migration of this release (#{Plastic::Graph::MIGRATIONS.baseline(:store)}, 20261119180000, #{UTC}, #{USAGE}, #{NODES}, #{NEEDS}, #{DRIVERS}, #{DEADLINE}, #{INPUTS}); run plastic update first",
      down(beta_2_home).refusal
  end

  def test_a_store_that_can_go_down_has_no_refusal
    assert_nil down(migrated_to_drop).refusal
  end

  def test_a_down_gives_the_store_the_layout_the_previous_release_wrote
    home = previous_home
    before = layout(home).fetch("knowledge_graph.db")
    migrate_store(home)
    back_to_drop(home)
    down(home).call

    assert_equal before, layout(home).fetch("knowledge_graph.db")
  end

  def test_a_down_answers_the_version_and_the_rows_it_put_back_by_table
    undone = down(migrated_to_drop).call

    assert_equal [DROP, { "document_revisions" => 1 }], [undone.version, undone.moved]
  end

  def test_a_down_and_then_an_update_give_back_the_migrated_store_and_its_legacy_rows
    home = migrated_to_drop
    before = [layout(home), contents(home, "knowledge_graph.db"), contents(home, "legacy.db")]
    down(home).call
    migrate_store(home)
    back_to_drop(home)

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
    home = migrated_to_drop
    write_document(home, "2", "spec.md", "new text")
    down(home).call

    assert_equal [["sha", "1", "intent.md", "old text", "then", "origin"], [Digest::SHA256.hexdigest("new text"), "2", "spec.md", "new text", "now", "origin"]], revisions(home)
  end

  def test_a_down_adds_no_revision_row_for_a_document_whose_kept_revision_came_back
    home = migrated_to_drop
    write_document(home, "1", "intent.md", "old text", "sha")
    down(home).call

    assert_equal [["sha", "1", "intent.md", "old text", "then", "origin"]], revisions(home)
  end

  def test_a_down_answers_the_revision_rows_it_built_by_table
    home = migrated_to_drop
    write_document(home, "2", "spec.md", "new text")

    assert_equal({ "document_revisions" => 1 }, down(home).call.built)
  end

  def test_a_store_whose_newest_recorded_migration_kept_nothing_is_refused_naming_that_migration
    assert_equal "migration #{Plastic::Graph::MIGRATIONS.baseline(:store)} kept nothing in legacy.db, so a down cannot undo it; restore a backup to go back", down(previous_home).refusal
  end

  # A migrated store whose node inputs migration, deadline migration, driver migration, roadmap migration, node columns migration, run usage migration, time migration, page migration and trim went down, so the report migration is the newest it records.
  def past_trim = migrated_previous_home.tap { |home| 9.times { down(home).call } }

  def test_the_report_migration_goes_down_by_removing_its_version_alone
    home = past_trim
    before = untouched(home)
    undone = down(home).call

    assert_equal [REPORTS, {}, false, true], [undone.version, undone.moved, recorded(home).include?(REPORTS), recorded(home).include?(DROP)]
    assert_equal before, untouched(home)
  end

  def untouched(home) = [layout(home), contents(home, "knowledge_graph.db").except("schema_migrations"), contents(home, "legacy.db")]

  def test_the_report_migration_has_no_refusal
    assert_nil down(past_trim).refusal
  end

  # A store of the previous release with a current revision beside the earlier one, and a revision of a path the sync never reads.
  def with_current_revision(home)
    SQLite3::Database.open(alpha_file(home, "knowledge_graph.db")) do |database|
      database.execute("INSERT INTO document_revisions VALUES (?, ?, ?, ?, ?, ?)", ["cur", "1", "intent.md", "new text", "now", "origin"])
      database.execute("INSERT INTO document_revisions VALUES (?, ?, ?, ?, ?, ?)", ["tmp", "1", "resources/tmp/x.md", "scratch", "now", "origin"])
      database.execute("INSERT INTO documents (intent_id, path, body, updated_at, origin_id) VALUES (?, ?, ?, ?, ?)", ["1", "intent.md", "new text", "now", "origin"])
      database.execute("INSERT INTO document_heads (intent_id, path, sha256, updated_at, origin_id) VALUES (?, ?, ?, ?, ?)", ["1", "intent.md", "cur", "now", "origin"])
    end
    home
  end

  def test_a_down_after_the_smaller_keep_restores_the_same_revision_rows_of_the_paths_the_sync_reads
    home = with_current_revision(previous_home)
    migrate_store(home)
    back_to_drop(home)
    down(home).call

    assert_equal [["cur", "1", "intent.md", "new text", "now", "origin"], ["sha", "1", "intent.md", "old text", "then", "origin"]], revisions(home).sort
  end
end
