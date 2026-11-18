# frozen_string_literal: true

require_relative "../../../test_helper"

class SchemaRunnerHomeTest < Plastic::TestCase
  include BackupHomes
  include OldLayoutHomes

  Runner = Plastic::Graph::SchemaRunner
  NOW = Time.utc(2026, 11, 16, 12, 0, 0)

  def copies(home) = Dir.glob(File.join(home, "backups", "local-*.db"))

  def test_an_old_layout_home_leaves_one_checked_copy_of_local_db_at_version_zero
    home = old_layout(fresh_home)
    Runner.new(home:, now: NOW).call

    assert_equal [File.join(home, "backups", "local-20261116120000.db")], copies(home)
    assert_equal [nil, "ok"], [recorded_versions(copies(home).first), read_value(copies(home).first, "PRAGMA quick_check")]
  end

  def seed_local_rows(home)
    SQLite3::Database.new(File.join(home, "local.db")).tap do |db|
      db.execute("INSERT INTO routine_runs (store, tool, subject) VALUES ('alpha', 'intent new', '7')")
      db.execute("INSERT INTO sessions (session_id, harness) VALUES ('s-1', 'claude-code')")
    end.close
  end

  def rows_of(home, table) = SQLite3::Database.new(File.join(home, "plastic.db"), readonly: true).execute("SELECT * FROM #{table}")

  def test_a_home_with_local_db_becomes_plastic_db_with_every_row
    home = old_layout(fresh_home)
    seed_local_rows(home)
    Runner.new(home:, now: NOW).call

    assert_equal [1, 1], %w[command_runs sessions].map { |table| rows_of(home, table).size }
    assert_equal [true, false], [File.exist?(File.join(home, "plastic.db")), File.exist?(File.join(home, "local.db"))]
  end

  def test_the_migrated_home_database_has_no_routine_runs_or_backups_table
    home = old_layout(fresh_home)
    Runner.new(home:, now: NOW).call
    tables = SQLite3::Database.new(File.join(home, "plastic.db"), readonly: true).execute("SELECT name FROM sqlite_master WHERE type = 'table'").flatten

    assert_empty tables & %w[routine_runs backups]
  end

  def test_the_copy_taken_before_the_rename_holds_the_rows_of_local_db
    home = old_layout(fresh_home)
    seed_local_rows(home)
    Runner.new(home:, now: NOW).call

    assert_equal [["alpha", "intent new", "7"]], SQLite3::Database.new(copies(home).first, readonly: true).execute("SELECT store, tool, subject FROM routine_runs").map { |row| row.first(3) }
  end

  def test_a_home_that_is_current_leaves_no_copy
    home = fresh_home
    Runner.new(home:, now: NOW).call

    assert_empty copies(home)
  end

  def test_a_home_whose_migration_fails_gives_its_reason
    home = old_layout(fresh_home)
    SQLite3::Database.new(File.join(home, "local.db")).tap { |db| db.execute('CREATE TABLE "command_runs"("store" TEXT)') }.close
    report = Runner.new(home:, now: NOW).call

    assert_match(/\Ait could not be migrated \(plastic\.db: .*command_runs/, report.failed.fetch("home"))
    assert_nil recorded_versions(File.join(home, "plastic.db"))
  end

  def test_a_home_whose_copy_fails_gives_its_reason
    home = old_layout(fresh_home)
    File.write(File.join(home, "backups"), "a file where the folder should be")

    assert_match(/\Athe copy of its database failed \(.+\)\z/, Runner.new(home:, now: NOW).call.failed.fetch("home"))
  end

  def test_a_home_whose_copy_cannot_be_made_stays_behind_and_is_reported
    home = old_layout(fresh_home)
    File.write(File.join(home, "backups"), "a file where the folder should be")
    report = Runner.new(home:, now: NOW).call

    assert_equal [nil, ["home"]], [recorded_by_file(home).fetch(File.join(home, "local.db")), report.failed.keys]
  end

  # The home file as a beta.2 build left it: its tables, stamp 0 and no schema_migrations table.
  def unmigrated(home)
    SQLite3::Database.new(File.join(home, "plastic.db")).tap { |db| db.execute_batch("DROP TABLE schema_migrations; PRAGMA user_version = 0") }.close
  end

  def test_a_plastic_db_behind_the_newest_version_leaves_one_checked_copy_named_after_it
    home = fresh_home
    unmigrated(home)
    Runner.new(home:, now: NOW).call
    copy = Dir.glob(File.join(home, "backups", "plastic-*.db"))

    assert_equal [[File.join(home, "backups", "plastic-20261116120000.db")], [nil, "ok"]], [copy, [recorded_versions(copy.first), read_value(copy.first, "PRAGMA quick_check")]]
  end

  def test_a_local_db_already_at_the_newest_version_is_still_renamed_to_plastic_db
    home = fresh_home
    Plastic::Graph::Database::ConnectionPool.release(home)
    File.rename(File.join(home, "plastic.db"), File.join(home, "local.db"))
    report = Runner.new(home:, now: NOW).call

    assert_equal [true, false, []], [File.exist?(File.join(home, "plastic.db")), File.exist?(File.join(home, "local.db")), report.failed.keys]
  end

  def test_a_plastic_db_at_the_newest_version_leaves_no_copy
    home = fresh_home
    Runner.new(home:, now: NOW).call

    assert_empty Dir.glob(File.join(home, "backups", "plastic-*.db"))
  end

  def test_a_home_folder_that_refuses_the_rename_gives_a_reason_and_the_run_goes_on
    home = old_layout(fresh_home)
    FileUtils.mkdir_p(File.join(home, "backups"))
    File.chmod(0o555, home)
    report = Runner.new(home:, now: NOW).call

    assert_match(/\Ait could not be migrated \(.+\)\z/, report.failed.fetch("home"))
  ensure
    File.chmod(0o755, home)
  end
end
