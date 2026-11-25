# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/migration/migration_down"

class GraphLegacyPagesTest < Plastic::TestCase
  include PreviousStore

  NOW = Time.utc(2026, 11, 20, 9, 0, 0)
  PAGES = "20261120090000"
  ALL = [DROP, TRIM, PAGES].freeze

  def migrate(home) = migrate_store(home)

  def pages(home) = %w[page_count freelist_count].map { |pragma| alpha_rows(home, "legacy.db", "PRAGMA #{pragma}").flatten.first }

  def contents(home) = legacy_tables(home).to_h { |table| [table, alpha_rows(home, "legacy.db", "SELECT * FROM \"#{table}\"").sort_by(&:inspect)] }

  JUNK = <<~SQL
    CREATE TABLE junk(text TEXT);
    WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 60) INSERT INTO junk SELECT printf('%0400d', i) FROM n;
    DROP TABLE junk;
  SQL

  # A store that ran the drop and the trim as release 3.0.0-beta.5 shipped them, which left the freed pages in legacy.db: the owner's time rows stay in it, and a table that was dropped leaves free pages.
  def trimmed_home
    previous_home_with_times.tap do |home|
      migrate_without(home, [PAGES])
      SQLite3::Database.open(alpha_file(home, "legacy.db")) { |database| database.execute_batch(JUNK) }
    end
  end

  def test_the_trim_of_release_beta_5_left_free_pages_in_legacy_db
    assert_operator pages(trimmed_home).last, :>, 0
  end

  def test_the_migration_gives_every_free_page_of_legacy_db_back_and_says_how_many
    home = trimmed_home
    free = pages(home).last
    report = migrate(home)

    assert_equal [0, true], [pages(home).last, recorded(home).include?(PAGES)]
    assert_includes report.notes, "migrate: alpha gave #{free} free pages of legacy.db back to the disk"
  end

  def test_a_store_that_ran_the_trim_before_ends_the_same_as_one_that_runs_all_three_together
    apart = trimmed_home.tap { |home| migrate(home) }
    together = previous_home_with_times.tap { |home| migrate(home) }

    assert_equal [pages(apart), contents(apart)], [pages(together), contents(together)]
  end

  def test_the_line_names_one_page_in_the_singular_and_no_page_not_at_all
    lines = [1, 0].map { |pages| Plastic::Graph::LegacyPages::Result.new(pages:).line("alpha") }

    assert_equal ["migrate: alpha gave 1 free page of legacy.db back to the disk", nil], lines
  end

  def test_a_store_with_no_legacy_db_gets_none
    home = File.join(Dir.mktmpdir, ".plastic")
    Plastic::Graph.create(home:, store: "alpha")
    forget(home)
    SQLite3::Database.open(alpha_file(home, "knowledge_graph.db")) { |database| database.execute("DELETE FROM schema_migrations WHERE version = ?", [PAGES]) }
    migrate(home)

    assert_equal [false, true], [File.exist?(alpha_file(home, "legacy.db")), recorded(home).include?(PAGES)]
  end

  def test_the_migration_goes_down_by_removing_its_version_alone
    home = utc_down(trimmed_home.tap { |trimmed| migrate(trimmed) })
    before = contents(home)
    undone = Plastic::Graph::MigrationDown.new(home, "alpha", NOW).call

    assert_equal [PAGES, {}, false, true, before], [undone.version, undone.moved, recorded(home).include?(PAGES), recorded(home).include?(TRIM), contents(home)]
  end
end
