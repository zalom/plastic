# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeBackupWriterTest < Plastic::TestCase
  include BackupHomes

  Backup = Plastic::Graph::Knowledge::Backup

  def test_a_failed_copy_leaves_no_backup_folder_and_no_row
    home = fresh_home
    Plastic::Graph::Database::ConnectionPool.release(File.join(home, "stores", "alpha"))
    File.write(store_file(home, "work_graph"), "not a database")

    assert_raises(StandardError) { backup_at(home, at(2026, 1, 1, 10, 0, 0)) }
    assert_empty folder_names(home)
    assert_empty row_names(home)
  end

  def test_a_failed_row_insert_removes_the_folder
    home = fresh_home
    Plastic::Graph.open(home:, store: "alpha").databases.fetch(:home).execute("DROP TABLE backups")

    assert_raises(StandardError) { backup_at(home, at(2026, 1, 1, 10, 0, 0)) }
    assert_empty folder_names(home)
  end

  def test_the_row_counts_the_databases_and_digests_the_sorted_names_and_digests
    home = fresh_home
    row = backup_at(home, at(2026, 1, 1, 10, 0, 0))
    folder = File.join(backups_dir(home), "20260101100000")

    assert_equal [3, "alpha/20260101100000", Backup::Folders.new(File.join(home, "stores", "alpha")).digest("20260101100000")],
      row.values_at(:files, :name, :sha256)
    assert_equal row.fetch(:bytes), Dir.children(folder).sum { |file| File.size(File.join(folder, file)) }
  end
end
