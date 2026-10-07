# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeBackupWriterTest < Plastic::TestCase
  include BackupHomes

  Backup = Plastic::Graph::Knowledge::Backup

  def failing_backup(home)
    Plastic::Graph::Database::ConnectionPool.release(File.join(home, "stores", "alpha"))
    File.write(store_file(home, "work_graph"), "not a database")
    assert_raises(StandardError) { backup_at(home, at(2026, 1, 1, 10, 0, 0)) }
  end

  def test_a_failed_copy_leaves_no_row
    home = fresh_home
    failing_backup(home)

    assert_empty row_names(home)
  end

  def test_a_failed_copy_marks_the_folder_failed
    home = fresh_home
    failing_backup(home)

    assert_equal "failed", Backup::Folders.new(File.join(home, "stores", "alpha")).status("20260101100000")
  end

  def test_a_finished_backup_is_marked_done_with_its_goal
    home = fresh_home
    backup_at(home, at(2026, 1, 1, 10, 0, 0), databases: %w[work_graph])
    folders = Backup::Folders.new(File.join(home, "stores", "alpha"))

    assert_equal ["done", "partial:work_graph.db"], [folders.status("20260101100000"), folders.goal("20260101100000")]
  end

  def test_a_full_backup_has_the_goal_full
    home = fresh_home
    backup_at(home, at(2026, 1, 1, 10, 0, 0))

    assert_equal "full", Backup::Folders.new(File.join(home, "stores", "alpha")).goal("20260101100000")
  end

  def test_a_folder_without_a_status_file_is_unknown
    home = fresh_home
    FileUtils.mkdir_p(File.join(backups_dir(home), "20260101100000"))

    assert_equal "unknown", Backup::Folders.new(File.join(home, "stores", "alpha")).status("20260101100000")
  end

  def test_a_failed_row_insert_removes_the_folder
    home = fresh_home
    refusing = Object.new
    def refusing.transaction = raise(StandardError, "the row cannot be written")
    target = Backup::Target.new(refusing, File.join(home, "stores", "alpha"), "alpha", nil)
    publisher = Backup::Publisher.new(target, now: at(2026, 1, 1, 10, 0, 0))

    assert_raises(StandardError) { publisher.call }
    assert_empty folder_names(home)
  end

  def test_the_row_counts_the_databases_and_digests_the_sorted_names_and_digests
    home = fresh_home
    row = backup_at(home, at(2026, 1, 1, 10, 0, 0))
    folders = Backup::Folders.new(File.join(home, "stores", "alpha"))

    assert_equal [3, "alpha/20260101100000", folders.digest("20260101100000")], row.values_at(:files, :name, :sha256)
    assert_equal row.fetch(:bytes), folders.bytes("20260101100000")
  end

  def test_a_store_with_no_database_has_nothing_to_back_up
    writer = Backup::Writer.new(Dir.mktmpdir, "alpha", now: at(2026, 1, 1, 10, 0, 0))

    assert_raises(Backup::Writer::Error) { writer.call }
  end
end
