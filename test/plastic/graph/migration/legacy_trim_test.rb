# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/migration/migration_down"
require_relative "../../../../lib/plastic/graph/migration/migration_purge"

class GraphLegacyTrimTest < Plastic::TestCase
  include PreviousStore

  NOW = Time.utc(2026, 11, 19, 13, 0, 0)
  REVISIONS = "SELECT sha256 FROM document_revisions_#{PreviousStore::DROP} ORDER BY sha256".freeze

  def migrate(home, released) = Plastic::Graph::SchemaRunner.new(home:, now: MIGRATED_AT, selection: Plastic::Graph::Knowledge::SyncSelection.none, released:).call.tap { forget(home) }

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

  # A store that ran the drop as release 3.0.0-beta.4 shipped it, before the trim.
  def dropped_home = previous_home_with_revisions.tap { |home| migrate(home, [DROP]) }

  def test_the_drop_keeps_every_revision_and_each_removed_sqlar_row_as_release_beta_4_did
    home = dropped_home

    assert_equal [["document_revisions_#{DROP}", "sqlar_#{DROP}"], %w[cur sha tmp], false],
      [legacy_tables(home), kept_revisions(home), recorded(home).include?(TRIM)]
  end

  def test_the_trim_leaves_only_the_earlier_texts_of_read_paths_and_no_sqlar_row
    home = dropped_home
    migrate(home, [DROP, TRIM])

    assert_equal [["document_revisions_#{DROP}"], %w[sha], true], [legacy_tables(home), kept_revisions(home), recorded(home).include?(TRIM)]
  end

  def test_a_store_that_runs_the_drop_and_the_trim_in_one_run_ends_the_same_as_one_that_ran_them_apart
    apart = dropped_home.tap { |home| migrate(home, [DROP, TRIM]) }
    together = previous_home_with_revisions.tap { |home| migrate(home, [DROP, TRIM]) }

    assert_equal contents(apart), contents(together)
  end

  def test_the_trim_names_what_it_removed_from_legacy_db
    home = dropped_home

    assert_includes migrate(home, [DROP, TRIM]).notes, "migrate: alpha trimmed 3 rows from legacy.db that a down rebuilds or that no sync reads"
  end

  def test_while_the_switch_is_off_the_trim_stays_held_with_the_drop
    home = previous_home_with_revisions
    migrate(home, [])

    assert_equal [false, false], [recorded(home).include?(DROP), recorded(home).include?(TRIM)]
  end

  def test_the_trim_of_a_store_whose_kept_rows_were_purged_removes_nothing
    home = dropped_home
    Plastic::Graph::MigrationPurge.new(home, "alpha", NOW).call(DROP)
    forget(home)
    report = migrate(home, [DROP, TRIM])

    assert_equal [["alpha"], [], true], [report.migrated, legacy_tables(home), recorded(home).include?(TRIM)]
  end

  def test_the_trim_goes_down_by_removing_its_version_alone
    home = utc_down(dropped_home.tap { |dropped| migrate(dropped, [DROP, TRIM]) })
    before = contents(home)
    undone = Plastic::Graph::MigrationDown.new(home, "alpha", NOW).call

    assert_equal [TRIM, {}, false, before], [undone.version, undone.moved, recorded(home).include?(TRIM), contents(home)]
  end
end
