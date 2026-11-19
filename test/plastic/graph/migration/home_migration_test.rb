# frozen_string_literal: true

require_relative "../../../test_helper"

class SchemaHomeMigrationTest < Plastic::TestCase
  include BackupHomes
  include OldLayoutHomes

  Runner = Plastic::Graph::SchemaRunner
  NOW = Time.utc(2026, 11, 16, 12, 0, 0)

  def tables_of(path) = layout_of(path).select { |type, _name, _sql| type == "table" }.to_h { |_type, name, sql| [name, sql] }

  def test_a_local_db_migrates_to_the_tables_of_a_new_plastic_db
    home = old_layout(fresh_home)
    Runner.new(home:, now: NOW, selection: Plastic::Graph::Knowledge::SyncSelection.none).call

    assert_equal tables_of(File.join(fresh_home, "plastic.db")).keys, tables_of(File.join(home, "plastic.db")).keys
  end

  def test_the_columns_of_every_table_match_a_new_plastic_db
    home = old_layout(fresh_home)
    Runner.new(home:, now: NOW, selection: Plastic::Graph::Knowledge::SyncSelection.none).call

    assert_equal columns_by_table(File.join(fresh_home, "plastic.db")), columns_by_table(File.join(home, "plastic.db"))
  end

  def test_the_migrated_home_records_every_home_version
    home = old_layout(fresh_home)
    Runner.new(home:, now: NOW, selection: Plastic::Graph::Knowledge::SyncSelection.none).call

    assert_equal Plastic::Graph::MIGRATIONS.versions(:home), recorded_versions(File.join(home, "plastic.db"))
  end

  def test_a_failing_statement_records_no_version_and_leaves_the_backup_in_place
    home = old_layout(fresh_home)
    SQLite3::Database.new(File.join(home, "local.db")).tap { |db| db.execute('CREATE TABLE "command_runs"("store" TEXT)') }.close
    Runner.new(home:, now: NOW, selection: Plastic::Graph::Knowledge::SyncSelection.none).call

    assert_equal [nil, 1], [recorded_versions(File.join(home, "plastic.db")), Dir.glob(File.join(home, "backups", "local-*.db")).size]
  end

  def test_a_second_run_changes_no_byte_of_the_home_database
    home = old_layout(fresh_home)
    Runner.new(home:, now: NOW, selection: Plastic::Graph::Knowledge::SyncSelection.none).call
    Plastic::Graph::Database::ConnectionPool.release(home)
    before = File.binread(File.join(home, "plastic.db"))
    Runner.new(home:, now: NOW + 60, selection: Plastic::Graph::Knowledge::SyncSelection.none).call

    assert_equal before, File.binread(File.join(home, "plastic.db"))
  end
end
