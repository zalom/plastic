# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/migration/migration_down"

class GraphLegacyPagesTest < Plastic::TestCase
  include PreviousStore

  NOW = Time.utc(2026, 11, 20, 9, 0, 0)
  PAGES = "20261120090000"
  ALL = [DROP, TRIM, PAGES].freeze

  def migrate(home, released) = Plastic::Graph::SchemaRunner.new(home:, now: MIGRATED_AT, selection: Plastic::Graph::Knowledge::SyncSelection.none, released:).call.tap { forget(home) }

  def pages(home) = %w[page_count freelist_count].map { |pragma| alpha_rows(home, "legacy.db", "PRAGMA #{pragma}").flatten.first }

  def contents(home) = legacy_tables(home).to_h { |table| [table, alpha_rows(home, "legacy.db", "SELECT * FROM \"#{table}\"").sort_by(&:inspect)] }

  # A store that ran the drop and the trim as release 3.0.0-beta.5 shipped them, which left the freed pages in legacy.db.
  def trimmed_home = previous_home.tap { |home| migrate(home, [DROP, TRIM]) }

  def test_the_trim_of_release_beta_5_left_free_pages_in_legacy_db
    assert_operator pages(trimmed_home).last, :>, 0
  end

  def test_the_migration_gives_every_free_page_of_legacy_db_back_and_says_how_many
    home = trimmed_home
    free = pages(home).last
    report = migrate(home, ALL)

    assert_equal [0, true], [pages(home).last, recorded(home).include?(PAGES)]
    assert_includes report.notes, "migrate: alpha gave #{free} free pages of legacy.db back to the disk"
  end

  def test_a_store_that_ran_the_trim_before_ends_the_same_as_one_that_runs_all_three_together
    apart = trimmed_home.tap { |home| migrate(home, ALL) }
    together = previous_home.tap { |home| migrate(home, ALL) }

    assert_equal [pages(apart), contents(apart)], [pages(together), contents(together)]
  end

  def test_a_store_with_no_legacy_db_gets_none
    home = File.join(Dir.mktmpdir, ".plastic")
    Plastic::Graph.create(home:, store: "alpha")
    forget(home)
    SQLite3::Database.open(alpha_file(home, "knowledge_graph.db")) { |database| database.execute("DELETE FROM schema_migrations WHERE version = ?", [PAGES]) }
    migrate(home, ALL)

    assert_equal [false, true], [File.exist?(alpha_file(home, "legacy.db")), recorded(home).include?(PAGES)]
  end

  def test_while_the_switch_is_off_the_migration_stays_held_with_the_trim
    home = trimmed_home
    free = pages(home)
    migrate(home, [])

    assert_equal [false, free], [recorded(home).include?(PAGES), pages(home)]
  end

  def test_the_migration_goes_down_by_removing_its_version_alone
    home = trimmed_home.tap { |trimmed| migrate(trimmed, ALL) }
    before = contents(home)
    undone = Plastic::Graph::MigrationDown.new(home, "alpha", NOW).call

    assert_equal [PAGES, {}, false, true, before], [undone.version, undone.moved, recorded(home).include?(PAGES), recorded(home).include?(TRIM), contents(home)]
  end
end
