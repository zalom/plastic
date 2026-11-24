# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/migration/migration_down"

class GraphMistakenRowsTest < Plastic::TestCase
  include PreviousStore

  CLEANUP = "20261124150000"
  MISTAKEN = "document_revisions_20261119000000"
  OWNER = "changed_values_20261121090000"

  # A current store whose legacy.db holds the mistaken copy of document_revisions and a table of the owner's, with the cleanup still to run.
  def kept_home(with_owner: true)
    home = File.join(Dir.mktmpdir, ".plastic")
    Plastic::Graph.create(home:, store: "alpha")
    forget(home)
    SQLite3::Database.open(alpha_file(home, "knowledge_graph.db")) { |database| database.execute("DELETE FROM schema_migrations WHERE version = ?", [CLEANUP]) }
    SQLite3::Database.open(alpha_file(home, "legacy.db")) { |database| database.execute_batch(kept_sql(with_owner)) }
    home
  end

  def kept_sql(with_owner)
    rows = Array.new(40) { |index| "INSERT INTO #{MISTAKEN} VALUES ('sha#{index}', 'a long earlier text of a spec, #{"x" * 400}');" }.join("\n")
    owner = with_owner ? "CREATE TABLE #{OWNER}(old TEXT); INSERT INTO #{OWNER} VALUES ('2026-11-01T10:00:00+01:00');" : ""
    "PRAGMA auto_vacuum = INCREMENTAL;\nCREATE TABLE #{MISTAKEN}(sha256 TEXT, body TEXT);\n#{rows}\n#{owner}"
  end

  def migrate(home) = Plastic::Graph::SchemaRunner.new(home:, now: MIGRATED_AT, selection: Plastic::Graph::Knowledge::SyncSelection.none, released: Plastic::Graph::MigrationList::HELD.keys).call.tap { forget(home) }

  def test_the_migration_deletes_the_mistaken_table_and_keeps_the_owners_data
    home = kept_home
    migrate(home)

    assert_equal [[OWNER], [["2026-11-01T10:00:00+01:00"]], true],
      [legacy_tables(home), alpha_rows(home, "legacy.db", "SELECT old FROM #{OWNER}"), recorded(home).include?(CLEANUP)]
  end

  def test_the_migration_leaves_no_copy_of_the_rows_on_the_disk
    home = kept_home
    migrate(home)

    assert_equal [0, false], [alpha_rows(home, "legacy.db", "PRAGMA freelist_count").flatten.first, File.binread(alpha_file(home, "legacy.db")).include?("a long earlier text")]
  end

  def test_the_migration_says_how_many_rows_it_deleted
    report = migrate(kept_home)

    assert_includes report.notes, "migrate: alpha deleted 40 rows of document_revisions from legacy.db, an agent's mistake with no copy and no undo"
  end

  def test_a_store_with_no_mistaken_table_changes_nothing_and_says_nothing
    home = kept_home
    SQLite3::Database.open(alpha_file(home, "legacy.db")) { |database| database.execute("DROP TABLE #{MISTAKEN}") }
    report = migrate(home)

    assert_equal [[OWNER], [], true], [legacy_tables(home), report.notes, recorded(home).include?(CLEANUP)]
  end

  def test_a_store_with_no_legacy_db_gets_none
    home = kept_home
    File.delete(alpha_file(home, "legacy.db"))
    migrate(home)

    assert_equal [false, true], [File.exist?(alpha_file(home, "legacy.db")), recorded(home).include?(CLEANUP)]
  end

  def test_the_migration_goes_down_by_removing_its_version_alone
    home = kept_home
    migrate(home)
    # The driver mode migration is newer, so its down comes first.
    undone = 2.times.map { Plastic::Graph::MigrationDown.new(home, "alpha", MIGRATED_AT).call }.last

    assert_equal [CLEANUP, {}, false, [OWNER]], [undone.version, undone.moved, recorded(home).include?(CLEANUP), legacy_tables(home)]
  end

  def test_the_migration_needs_no_switch
    refute_includes Plastic::Graph::MigrationList::HELD.keys, CLEANUP
  end
end
