# frozen_string_literal: true

require_relative "../../../test_helper"

class GraphBackupStoreBackupsTest < Plastic::TestCase
  include BackupHomes

  FIRST = Time.utc(2026, 1, 1, 10, 0, 0)

  def backups(home) = Plastic::Graph.open(home:, store: "alpha").work.backups

  def test_a_preview_names_the_folder_and_the_databases_that_exist
    plan = backups(fresh_home).plan

    assert_equal %w[knowledge_graph references work_graph], plan.fetch(:databases).sort
    assert_match(/\A\d{14}\z/, plan.fetch(:folder))
  end

  def test_a_folder_with_no_row_is_listed_as_having_no_row
    home = fresh_home
    FileUtils.mkdir_p(File.join(backups_dir(home), "20260101100000"))

    assert_equal ["no row"], backups(home).entries.map(&:flag)
  end

  def test_a_written_backup_is_listed_with_no_flag_and_found_as_the_latest_done
    home = fresh_home
    backup_at(home, FIRST)

    assert_equal [nil, "20260101100000"], [backups(home).entries.first.flag, backups(home).latest_done]
  end

  def test_a_backup_whose_folder_changed_is_listed_as_changed
    home = fresh_home
    backup_at(home, FIRST)
    File.write(Dir.glob(File.join(backups_dir(home), "20260101100000", "work_graph-*.db")).first, "altered")

    assert_equal ["changed"], backups(home).entries.map(&:flag)
  end
end
