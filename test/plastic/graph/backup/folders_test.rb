# frozen_string_literal: true

require_relative "../../../test_helper"

class GraphBackupFoldersTest < Plastic::TestCase
  Folders = Plastic::Graph::Backup::Folders

  def setup
    super
    @root = Dir.mktmpdir
    @folders = Folders.new(@root)
    FileUtils.mkdir_p(@folders.path("20260101100000"))
    File.write(File.join(@folders.path("20260101100000"), "work_graph-x.db"), "rows")
    @folders.write_report("20260101100000", status: "done", goal: "full")
  end

  def teardown
    FileUtils.remove_entry(@root)
    super
  end

  def test_recording_the_digest_adds_it_to_the_status_file_and_keeps_the_rest
    @folders.record_digest("20260101100000")
    report = @folders.report("20260101100000")

    assert_equal [@folders.digest("20260101100000"), "done", "full"], report.values_at("digest", "status", "goal")
  end

  def test_the_digest_changes_when_a_file_changes
    before = @folders.digest("20260101100000")
    File.write(File.join(@folders.path("20260101100000"), "work_graph-x.db"), "other")

    refute_equal before, @folders.digest("20260101100000")
  end
  def test_the_folder_name_is_spelled_once_for_the_store_ignore_list_and_the_sync_preview
    ignored = Plastic::Graph::Knowledge::StoreFolder::IGNORED
    mirrored = Plastic::Graph::Knowledge::Sync::Preview::Mirror::BACKUPS

    assert_equal [File.join(@root, Folders::NAME), Folders::NAME, true], [@folders.dir, mirrored, ignored.include?("#{Folders::NAME}/")]
  end
end
