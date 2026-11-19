# frozen_string_literal: true

require "digest"
require "json"
require_relative "../../../test_helper"

class SchemaRunnerTest < Plastic::TestCase
  include BackupHomes
  include OldLayoutHomes

  Runner = Plastic::Graph::SchemaRunner
  NOW = Time.utc(2026, 11, 16, 12, 0, 0)

  def run_runner(home, **options) = Runner.new(home:, now: NOW, selection: Plastic::Graph::Knowledge::SyncSelection.none, **options).call

  def old_home = old_layout(fresh_home)

  def store_files(home, slug = "alpha") = Dir.glob(File.join(home, "stores", slug, "*.db")).sort

  def test_a_report_names_each_store_that_stays_behind_in_one_line
    report = Runner::Report.new(migrated: ["beta"], failed: { "alpha" => "its backup failed", "gamma" => "it is locked" })

    assert_equal ["migrate: alpha stays behind because its backup failed; fix the cause and run plastic update",
      "migrate: gamma stays behind because it is locked; fix the cause and run plastic update"], report.behind_lines
  end

  def test_a_report_with_no_store_behind_has_no_lines
    assert_empty Runner::Report.new(migrated: ["alpha"], failed: {}).behind_lines
  end

  def test_the_lines_of_a_report_are_the_stores_behind_and_then_the_notes
    report = Runner::Report.new(migrated: ["beta"], failed: { "alpha" => "it is locked" }, notes: ["migrate: beta keeps a row"])

    assert_equal ["migrate: alpha stays behind because it is locked; fix the cause and run plastic update", "migrate: beta keeps a row"], report.lines
  end

  def test_an_old_layout_home_migrated_through_every_migration_has_the_layout_of_a_new_database
    home = old_home
    run_runner(home)

    assert_equal layouts(fresh_home), layouts(home)
  end

  def test_the_home_and_the_knowledge_database_record_their_versions_and_the_other_store_databases_record_none
    home = old_home
    run_runner(home)
    recorded = recorded_by_file(home).group_by { |path, _| File.basename(path) }.transform_values { |pairs| pairs.map(&:last).uniq }
    list = Plastic::Graph::MIGRATIONS

    assert_equal({ "plastic.db" => [list.versions(:home)], "knowledge_graph.db" => [list.versions(:store)], "work_graph.db" => [nil], "retrieval_graph.db" => [nil] }, recorded)
  end

  def ledger(home) = read_file(File.join(home, "plastic.db"), "SELECT store, version, event, at, rows, undoable FROM store_migrations ORDER BY id")

  def kept_counts(home, version)
    tables = read_file(store_path(home, "legacy.db"), "SELECT name FROM sqlite_master WHERE type = 'table'").flatten.select { |name| name.end_with?("_#{version}") }
    tables.to_h { |name| [name.delete_suffix("_#{version}"), read_file(store_path(home, "legacy.db"), "SELECT count(*) FROM \"#{name}\"").flatten.first] }
  end

  def test_each_migration_that_ran_on_a_store_adds_an_up_row_to_the_ledger_with_what_it_kept_in_legacy_db
    home = old_home
    run_runner(home)
    rows = ledger(home).select { |row| row.first == "alpha" }
    kept = JSON.generate(kept_counts(home, "20261119000000").sort.to_h)

    assert_equal [["alpha", "20261117000000", "up", "2026-11-16T12:00:00Z", "{}", 0], ["alpha", "20261119000000", "up", "2026-11-16T12:00:00Z", kept, 1]],
      rows.map { |row| [*row.first(4), JSON.generate(JSON.parse(row[4]).sort.to_h), row[5]] }
  end

  def test_a_run_on_current_stores_adds_no_row_to_the_ledger
    home = fresh_home
    run_runner(home)

    assert_empty ledger(home)
  end

  def test_a_run_whose_home_stays_behind_notes_that_the_ledger_does_not_record_its_store_migrations
    home = old_home
    SQLite3::Database.new(File.join(home, "local.db")).tap { |db| db.execute('CREATE TABLE "command_runs"("store" TEXT)') }.close
    report = run_runner(home)

    assert_includes report.notes, "migrate: plastic.db stays behind, so its ledger does not record the migrations of alpha, beta"
  end

  def test_a_backup_of_the_store_is_taken_first_and_says_it_is_the_migration_backup
    home = old_home
    run_runner(home)
    report = Plastic::Graph::Backup::Folders.new(File.join(home, "stores", "alpha")).report(folder_names(home).first)

    assert_equal ["migration", 0, "done"], report.values_at("reason", "version", "status")
  end

  def test_a_fresh_backup_does_not_stop_the_runner_from_taking_its_own
    home = old_home
    Plastic::Graph::Backup::Writer.new(File.join(home, "stores", "alpha"), "alpha", now: NOW - 60).call
    run_runner(home)

    assert_equal 2, folder_names(home).size
  end

  def test_a_home_that_is_current_changes_no_byte_and_takes_no_backup
    home = old_home
    run_runner(home)
    before = file_bytes(home)
    count = folder_names(home).size
    run_runner(home)

    assert_equal [before, count], [file_bytes(home), folder_names(home).size]
  end

  def test_a_store_whose_backup_fails_stays_behind_and_the_other_store_migrates
    home = old_home
    Plastic::Graph::Database::ConnectionPool.release(home)
    File.write(store_file(home, "work_graph"), "not a database")
    before = bytes_in(home, "/alpha/")
    report = run_runner(home)

    assert_equal [["alpha"], before], [report.failed.keys, bytes_in(home, "/alpha/")]
    assert_equal Plastic::Graph::MIGRATIONS.versions(:store), recorded_versions(store_file(home, "knowledge_graph", "beta"))
  end

  def test_a_store_whose_backup_folder_cannot_be_written_stays_behind
    home = old_home
    FileUtils.mkdir_p(File.join(home, "stores", "alpha", "backups"), mode: 0o555)
    bytes_in(home, "/alpha/")
    report = run_runner(home)

    assert_equal [["alpha"], [nil]], [report.failed.keys, versions_in(home, "/alpha/")]
  end

  def test_backup_migrate_restore_and_migrate_again_give_equal_row_digests
    home = old_home
    run_runner(home)
    migrated = store_digests(home).except("retrieval_graph.db")
    Plastic::Graph::Database::ConnectionPool.release(home)
    restore_call(home, "--store", "alpha", "--latest")

    assert_equal [Plastic::Graph::MIGRATIONS.versions(:store)], versions_in(home, "/alpha/knowledge_graph.db")
    assert_equal migrated, store_digests(home).except("retrieval_graph.db")
  end

  def bytes_in(home, part) = file_bytes(home).select { |path, _| path.include?(part) }

  def versions_in(home, part) = recorded_by_file(home).select { |path, _| path.include?(part) }.values.uniq

  def store_digests(home) = store_files(home).to_h { |path| [File.basename(path), row_digest(path)] }
end
