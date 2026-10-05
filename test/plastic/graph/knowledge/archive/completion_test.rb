# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../scripts/lib/plastic/graph/knowledge/archive/writer"

class KnowledgeArchiveCompletionTest < Plastic::TestCase
  Archive = Plastic::Graph::Knowledge::Archive

  def setup
    super
    @intent = open_intent("Target", status: "future")
    @removed = []
    work = store_graphs.databases[:work]
    Archive::Capture.new(work, folder, retrieval.origin_id, session: nil).capture(@intent)
  end

  def snapshot(intent_id) = Archive::Snapshot.new(store_graphs.databases[:work], intent_id, retrieval.origin_id)

  def completion
    index = Archive::SnapshotIndex.new(store_graphs.databases[:knowledge], retrieval.origin_id)
    Archive::Completion.new(index, folder, snapshot: method(:snapshot), remove_printed: @removed.method(:push))
  end

  def test_completion_indexes_the_snapshot_removes_the_folder_and_clears_its_printed_files
    completion.call(@intent)

    assert_includes retrieval.documents("1").map(&:path), @intent.file
    refute_path_exists folder.path(@intent.dir)
    assert_equal [@intent.dir], @removed
  end

  def test_a_folder_changed_since_the_capture_is_kept
    File.write(folder.path("#{@intent.dir}/new.md"), "new")

    assert_raises(Plastic::Graph::Knowledge::Archive::Tree::Error, SystemCallError) { completion.call(@intent) }
    assert_path_exists folder.path("#{@intent.dir}/new.md")
  end
end
