# frozen_string_literal: true

require_relative "../../../test_helper"

class KnowledgeBackupTest < Plastic::TestCase
  include BackupHomes

  NAME = "alpha/20260101100000"

  def row = Plastic::Graph.open(home: @flag_home, store: "alpha").retrieval.backups.find { |backup| backup.name == NAME }

  def setup
    super
    @flag_home = fresh_home
    backup_at(@flag_home, at(2026, 1, 1, 10, 0, 0))
  end

  def test_a_folder_that_matches_its_digest_has_no_flag
    assert_nil row.flag(@flag_home)
  end

  def test_a_folder_whose_file_changed_is_flagged_changed
    File.write(Dir.glob(File.join(backups_dir(@flag_home), "*", "work_graph-*.db")).first, "x", mode: "a")

    assert_equal "changed", row.flag(@flag_home)
  end

  def test_a_row_with_no_folder_is_flagged_missing
    FileUtils.rm_rf(File.join(backups_dir(@flag_home), "20260101100000"))

    assert_equal "missing", row.flag(@flag_home)
  end
end
