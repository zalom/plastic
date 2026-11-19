# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../test_helpers/beta_2_store"
require_relative "../../../test_helpers/schema_versions"

class GraphBackupIntegrityTest < Plastic::TestCase
  include BackupHomes

  Integrity = Plastic::Graph::Backup::Integrity

  def backup_file(home, name)
    folder = backup_at(home, at(2026, 1, 1, 10, 0, 0)).fetch(:name).split("/").last
    File.join(backups_dir(home), folder, "#{name}-#{folder}.db")
  end

  def test_a_sound_backup_file_passes
    home = fresh_home

    assert_nil Integrity.new(backup_file(home, "work_graph"), "work_graph", version: Plastic::Graph::MIGRATIONS.newest(:store).to_i).call
  end

  def test_a_file_that_is_not_a_database_is_rejected
    path = File.join(Dir.mktmpdir, "work_graph-1.db")
    File.write(path, "not a database" * 100)
    error = assert_raises(Integrity::Rejected) { Integrity.new(path, "work_graph", version: 1).call }

    assert_includes error.message, "is not a readable database"
  end

  def test_a_missing_file_is_rejected
    path = File.join(Dir.mktmpdir, "absent.db")
    error = assert_raises(Integrity::Rejected) { Integrity.new(path, "work_graph", version: 1).call }

    assert_includes error.message, path
  end

  def damaged_file
    path = File.join(Dir.mktmpdir, "work_graph-1.db")
    database = SQLite3::Database.new(path)
    database.execute("CREATE TABLE t (a TEXT)")
    200.times { |n| database.execute("INSERT INTO t VALUES (?)", ["a" * 60 + n.to_s]) }
    database.close
    File.open(path, "r+b") { |file| file.pwrite("\x00".b * 100, 3 * 4096 - 200) }
    path
  end

  def test_a_database_whose_pages_are_damaged_fails_the_integrity_check
    path = damaged_file
    error = assert_raises(Integrity::Rejected) { Integrity.new(path, "work_graph", version: 1).call }

    assert_includes error.message, "fails the integrity check"
  end

  def test_a_beta_2_backup_file_passes_at_version_zero
    path = File.join(Dir.mktmpdir, "knowledge_graph-1.db")
    database = SQLite3::Database.new(path)
    database.execute_batch(File.read(File.join(Beta2Store::FOLDER, "knowledge_layout.sql")))
    database.close

    assert_nil Integrity.new(path, "knowledge_graph", version: 0).call
  end

  def test_a_database_that_lacks_the_schema_tables_is_rejected
    path = File.join(Dir.mktmpdir, "work_graph-1.db")
    SQLite3::Database.new(path).tap { |database| database.execute("CREATE TABLE other (id INTEGER)") }.close
    error = assert_raises(Integrity::Rejected) { Integrity.new(path, "work_graph", version: Plastic::Graph::MIGRATIONS.newest(:store).to_i).call }

    assert_includes error.message, "lacks the tables"
  end
end

class GraphBackupIntegrityVersionTest < Plastic::TestCase
  Integrity = Plastic::Graph::Backup::Integrity

  def work_file_without(*tables)
    path = File.join(Dir.mktmpdir, "work_graph-1.db")
    db = SQLite3::Database.new(path)
    db.execute_batch(File.read(File.join(Beta2Store::FOLDER, "work_layout.sql")))
    tables.each { |table| db.execute("DROP TABLE #{table}") }
    db.close
    path
  end

  def test_a_version_zero_backup_holding_every_table_of_beta_2_passes
    assert_nil Integrity.new(work_file_without, "work_graph", version: 0).call
  end

  def test_a_version_zero_backup_without_a_table_of_beta_2_is_rejected
    error = assert_raises(Integrity::Rejected) { Integrity.new(work_file_without("savepoints"), "work_graph", version: 0).call }

    assert_includes error.message, "lacks the tables savepoints"
  end

  def test_a_backup_of_the_beta_2_layout_at_the_newest_version_is_rejected_for_the_tables_it_lacks
    error = assert_raises(Integrity::Rejected) { Integrity.new(work_file_without, "work_graph", version: Plastic::Graph::MIGRATIONS.newest(:store).to_i).call }

    assert_includes error.message, "lacks the tables work_log"
  end

  def later_list
    probe = File.expand_path("../../../fixtures/migrations/add_probe_table.sql", __dir__)
    Plastic::Graph::MIGRATIONS.with(Plastic::Graph::SchemaMigration.new(kind: :store, version: "20991201000000", path: probe))
  end

  def baseline = Plastic::Graph::MIGRATIONS.baseline(:store).to_i

  def test_an_earlier_known_version_passes_on_the_quick_check_alone
    assert_nil Integrity.new(work_file_without("savepoints"), "work_graph", version: baseline, migrations: later_list).call
  end

  def test_the_newest_version_checks_the_declared_tables
    error = assert_raises(Integrity::Rejected) { Integrity.new(work_file_without, "work_graph", version: 20_991_201_000_000, migrations: later_list).call }

    assert_includes error.message, "lacks the tables work_log"
  end

  def test_a_version_below_the_newest_that_this_code_does_not_know_is_rejected
    error = assert_raises(Integrity::Rejected) { Integrity.new(work_file_without, "work_graph", version: baseline + 1, migrations: later_list).call }

    assert_includes error.message, "which this code does not know"
  end

  def test_a_version_above_the_newest_is_rejected
    error = assert_raises(Integrity::Rejected) { Integrity.new(work_file_without, "work_graph", version: SchemaVersions::UNKNOWN.to_i).call }

    assert_includes error.message, "newer than this code"
  end
end
