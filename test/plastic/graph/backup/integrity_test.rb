# frozen_string_literal: true

require_relative "../../../test_helper"

class GraphBackupIntegrityTest < Plastic::TestCase
  include BackupHomes

  Integrity = Plastic::Graph::Backup::Integrity

  def backup_file(home, name)
    folder = backup_at(home, at(2026, 1, 1, 10, 0, 0)).fetch(:name).split("/").last
    File.join(backups_dir(home), folder, "#{name}-#{folder}.db")
  end

  def test_a_sound_backup_file_passes
    home = fresh_home

    assert_nil Integrity.new(backup_file(home, "work_graph"), "work_graph", version: Plastic::Graph::SchemaSequences.newest(:store)).call
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

  def test_a_backup_without_the_new_table_restores
    path = File.join(Dir.mktmpdir, "knowledge_graph-1.db")
    database = SQLite3::Database.new(path)
    database.execute_batch(Plastic::Graph::SchemaStore1::Layout::TEXT.fetch(:knowledge))
    database.execute("DROP TABLE legacy_intents_data")
    database.close

    assert_nil Integrity.new(path, "knowledge_graph", version: 0).call
  end

  def test_a_database_that_lacks_the_schema_tables_is_rejected
    path = File.join(Dir.mktmpdir, "work_graph-1.db")
    SQLite3::Database.new(path).tap { |database| database.execute("CREATE TABLE other (id INTEGER)") }.close
    error = assert_raises(Integrity::Rejected) { Integrity.new(path, "work_graph", version: 1).call }

    assert_includes error.message, "lacks the tables"
  end
end

class GraphBackupIntegrityVersionTest < Plastic::TestCase
  Integrity = Plastic::Graph::Backup::Integrity

  def file_without(*tables)
    path = File.join(Dir.mktmpdir, "work_graph-1.db")
    db = SQLite3::Database.new(path)
    db.execute_batch(Plastic::Graph::SchemaStore1::Layout::TEXT.fetch(:work))
    %w[approvals verdicts].each { |table| db.execute("CREATE TABLE IF NOT EXISTS #{table} (intent_id TEXT)") }
    tables.each { |table| db.execute("DROP TABLE #{table}") }
    db.close
    path
  end

  def test_a_version_zero_backup_without_the_later_tables_passes
    assert_nil Integrity.new(file_without("approvals", "verdicts"), "work_graph", version: 0).call
  end

  def test_a_version_one_backup_without_a_table_of_version_one_is_rejected
    error = assert_raises(Integrity::Rejected) { Integrity.new(file_without("approvals"), "work_graph", version: 1).call }

    assert_includes error.message, "lacks the tables approvals"
  end

  def test_a_version_above_the_newest_is_rejected
    error = assert_raises(Integrity::Rejected) { Integrity.new(file_without, "work_graph", version: 99).call }

    assert_includes error.message, "newer than this code"
  end
end
