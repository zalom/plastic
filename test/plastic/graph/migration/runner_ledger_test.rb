# frozen_string_literal: true

require "json"
require_relative "../../../test_helper"

class SchemaRunnerLedgerTest < Plastic::TestCase
  include BackupHomes
  include OldLayoutHomes
  include PreviousStore

  Runner = Plastic::Graph::SchemaRunner
  NOW = Time.utc(2026, 11, 16, 12, 0, 0)
  DROP = "20261119000000"

  def run_runner(home) = Runner.new(home:, now: NOW, selection: Plastic::Graph::Knowledge::SyncSelection.none).call

  def old_home = old_layout(fresh_home)

  def ledger(home) = read_file(File.join(home, "plastic.db"), "SELECT store, version, event, at, moved, undoable FROM store_migrations ORDER BY id")

  def legacy(home, sql) = read_file(store_path(home, "legacy.db"), sql)

  def kept_counts(home)
    tables = legacy(home, "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE '%_#{DROP}' ORDER BY name").flatten
    tables.to_h { |name| [name.delete_suffix("_#{DROP}"), legacy(home, "SELECT count(*) FROM \"#{name}\"").flatten.first] }
  end

  # The versions an old store runs, each with whether a down can undo it: the first two cannot.
  UPS = [["20261117000000", 0], [DROP, 0], ["20261119180000", 1], [TRIM, 1], [PAGES, 1], [UTC, 1], [USAGE, 1], [NODES, 1], [NEEDS, 1],
    [DRIVERS, 1], [DEADLINE, 1], [INPUTS, 1], [EMPTY_ROADMAPS, 1], [LEFTOVERS, 1], [MISTAKES, 1], [DRIVER_MODE, 1], [DRIVER_AGENT, 1],
    [WORK_LOG_TEXT, 1], [OWN_IDS, 1], [PLACEHOLDERS, 1], [MERGES, 1]].freeze

  def test_each_migration_that_ran_on_a_store_adds_an_up_row_to_the_ledger
    home = old_home
    run_runner(home)

    assert_equal UPS.map { |version, undoable| ["alpha", version, "up", "2026-11-16T12:00:00Z", undoable] },
      ledger(home).select { |row| row.first == "alpha" }.map { |row| row.values_at(0, 1, 2, 3, 5) }
  end

  def test_the_up_row_of_the_drop_names_the_rows_it_kept_in_legacy_db_by_table_and_the_trim_removes_them
    home = old_home
    run_runner(home)
    moved = ledger(home).find { |row| row.first(2) == ["alpha", DROP] }[4]

    assert_equal [{ "sqlar" => 2 }, {}], [JSON.parse(moved).sort.to_h, kept_counts(home)]
  end

  def test_a_run_on_current_stores_adds_no_row_to_the_ledger
    home = fresh_home
    run_runner(home)

    assert_empty ledger(home)
  end

  def test_a_ledger_that_cannot_be_written_leaves_the_store_migrated_and_notes_why
    home = previous_home
    Plastic::Graph::Database.open_local(home)
    forget(home)
    SQLite3::Database.open(File.join(home, "plastic.db")) { |db| db.execute("CREATE TRIGGER refuse BEFORE INSERT ON store_migrations BEGIN SELECT RAISE(ABORT, 'refused'); END") }
    report = migrate_store(home)

    assert_includes recorded(home), DROP
    assert_match(/^migrate: the ledger in plastic\.db does not record the migrations of alpha \(/, report.notes.join("\n"))
  end

  def test_a_ledger_that_refuses_the_rows_of_one_store_names_the_stores_it_recorded_and_those_it_did_not
    home = previous_home
    FileUtils.cp_r(store_path(home, ""), File.join(home, "stores", "beta"))
    Plastic::Graph::Database.open_local(home)
    forget(home)
    SQLite3::Database.open(File.join(home, "plastic.db")) { |db| db.execute("CREATE TRIGGER refuse BEFORE INSERT ON store_migrations WHEN NEW.store = 'beta' BEGIN SELECT RAISE(ABORT, 'refused'); END") }
    report = migrate_store(home)

    assert_equal [["migrate: the ledger in plastic.db records the migrations of alpha but not those of beta (plastic.db: refused)"], ["alpha"]],
      [report.notes.grep(/ledger/), ledger(home).map(&:first).uniq]
  end

  def test_a_run_whose_home_stays_behind_notes_that_the_ledger_does_not_record_its_store_migrations
    home = old_home
    SQLite3::Database.new(File.join(home, "local.db")).tap { |db| db.execute('CREATE TABLE "command_runs"("store" TEXT)') }.close
    report = run_runner(home)

    assert_includes report.notes, "migrate: plastic.db stays behind, so its ledger does not record the migrations of alpha, beta"
  end
end
