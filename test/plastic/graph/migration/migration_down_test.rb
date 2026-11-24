# frozen_string_literal: true

require_relative "../../../test_helper"
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
    assert_equal "migration #{UTC} kept nothing in legacy.db, so a down cannot undo it; restore a backup to go back",
      down(migrated_to_owner, keeps: []).refusal
  end

  def test_a_store_from_before_the_baseline_is_refused_until_plastic_update_runs_it
    assert_equal "alpha has not run every migration of this release (#{Plastic::Graph::MIGRATIONS.baseline(:store)}, 20261119180000, #{UTC}, #{USAGE}, #{NODES}, #{NEEDS}, #{DRIVERS}, #{DEADLINE}, #{INPUTS}, #{EMPTY_ROADMAPS}, #{LEFTOVERS}, #{MISTAKES}, #{DRIVER_MODE}); run plastic update first",
      down(beta_2_home).refusal
  end

  def test_a_store_whose_newest_recorded_migration_kept_nothing_is_refused_naming_that_migration
    assert_equal "migration #{Plastic::Graph::MIGRATIONS.baseline(:store)} kept nothing in legacy.db, so a down cannot undo it; restore a backup to go back", down(previous_home).refusal
  end

  # A migrated store whose cleanup of the mistaken rows, leftover work tables migration, empty roadmap tables migration, node inputs migration, deadline migration, driver migration, roadmap migration, node columns migration, run usage migration, time migration, page migration and trim went down, so the report migration is the newest it records.
  def past_trim = previous_home_with_times.tap { |home| migrate_store(home) }.tap { |home| 13.times { down(home).call } }

  def test_the_report_migration_goes_down_by_removing_its_version_alone
    home = past_trim
    before = untouched(home)
    undone = down(home).call

    assert_equal [REPORTS, {}, false, true], [undone.version, undone.moved, recorded(home).include?(REPORTS), recorded(home).include?(DROP)]
    assert_equal before, untouched(home)
  end

  def untouched(home) = [layout(home), contents(home, "knowledge_graph.db").except("schema_migrations"), (contents(home, "legacy.db") if File.exist?(alpha_file(home, "legacy.db")))]

  def test_the_report_migration_has_no_refusal
    assert_nil down(past_trim).refusal
  end
end
