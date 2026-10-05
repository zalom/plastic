# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../scripts/lib/plastic/graph/knowledge/backup/folder_name"

class KnowledgeBackupFolderNameTest < Plastic::TestCase
  FolderName = Plastic::Graph::Knowledge::Backup::FolderName

  def backups_dir = File.join(@home, "backups")

  def test_the_name_is_fourteen_utc_digits_of_the_given_time
    assert_equal "20261005161530", FolderName.for(backups_dir, Time.utc(2026, 10, 5, 16, 15, 30))
  end

  def test_a_time_with_an_offset_is_named_by_its_utc_digits
    assert_equal "20261005141530", FolderName.for(backups_dir, Time.new(2026, 10, 5, 16, 15, 30, "+02:00"))
  end

  def test_a_taken_name_gets_the_next_free_suffix
    time = Time.utc(2026, 10, 5, 16, 15, 30)
    FileUtils.mkdir_p(File.join(backups_dir, "20261005161530"))

    assert_equal "20261005161530-1", FolderName.for(backups_dir, time)

    FileUtils.mkdir_p(File.join(backups_dir, "20261005161530-1"))

    assert_equal "20261005161530-2", FolderName.for(backups_dir, time)
  end
end
