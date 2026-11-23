# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/backup/folder_name"

class GraphBackupFolderNameTest < Plastic::TestCase
  FolderName = Plastic::Graph::Backup::FolderName

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

  def test_a_name_that_rolls_over_to_another_day_is_not_readable
    refute FolderName.readable?("20200231000000")
  end

  def test_a_name_with_a_field_out_of_range_is_not_readable
    refute FolderName.readable?("20201399000000")
  end

  def test_a_real_time_with_a_suffix_is_readable
    assert FolderName.readable?("20200229235959-2")
  end

  def test_a_folder_that_is_not_a_real_time_is_never_before_a_limit
    refute FolderName.before?("20200231000000", Time.utc(2030, 1, 1))
  end
end
