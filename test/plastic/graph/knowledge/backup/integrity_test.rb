# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeBackupIntegrityTest < Plastic::TestCase
  include BackupHomes

  Integrity = Plastic::Graph::Knowledge::Backup::Integrity

  def backup_file(home, name)
    folder = backup_at(home, at(2026, 1, 1, 10, 0, 0)).fetch(:name).split("/").last
    File.join(backups_dir(home), folder, "#{name}-#{folder}.db")
  end

  def test_a_sound_backup_file_passes
    home = fresh_home

    assert_nil Integrity.new(backup_file(home, "work_graph"), "work_graph").call
  end

  def test_a_file_that_is_not_a_database_is_rejected
    path = File.join(Dir.mktmpdir, "work_graph-1.db")
    File.write(path, "not a database" * 100)
    error = assert_raises(Integrity::Rejected) { Integrity.new(path, "work_graph").call }

    assert_includes error.message, "is not a readable database"
  end

  def test_a_missing_file_is_rejected
    path = File.join(Dir.mktmpdir, "absent.db")
    error = assert_raises(Integrity::Rejected) { Integrity.new(path, "work_graph").call }

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
    error = assert_raises(Integrity::Rejected) { Integrity.new(path, "work_graph").call }

    assert_includes error.message, "fails the integrity check"
  end

  def test_a_backup_without_the_new_table_restores
    path = File.join(Dir.mktmpdir, "knowledge_graph-1.db")
    database = SQLite3::Database.new(path)
    database.execute_batch(Plastic::Graph::Schema.fetch(:knowledge))
    database.execute("DROP TABLE legacy_intents_data")
    database.close

    assert_nil Integrity.new(path, "knowledge_graph").call
  end

  def test_a_database_that_lacks_the_schema_tables_is_rejected
    path = File.join(Dir.mktmpdir, "work_graph-1.db")
    SQLite3::Database.new(path).tap { |database| database.execute("CREATE TABLE other (id INTEGER)") }.close
    error = assert_raises(Integrity::Rejected) { Integrity.new(path, "work_graph").call }

    assert_includes error.message, "lacks the tables"
  end
end
