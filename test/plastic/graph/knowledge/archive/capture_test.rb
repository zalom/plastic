# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../scripts/lib/plastic/graph/knowledge/archive/writer"

class KnowledgeArchiveCaptureTest < Plastic::TestCase
  Archive = Plastic::Graph::Knowledge::Archive

  def setup
    super
    @intent = open_intent("Target", status: "future")
  end

  def capture = Archive::Capture.new(store_graphs.databases[:work], folder, retrieval.origin_id, session: "s-1")

  def test_capture_keeps_the_snapshot_and_marks_the_intent_archived
    capture.capture(@intent)

    assert retrieval.archived?("1")
    assert_includes Archive::Snapshot.new(store_graphs.databases[:work], "1", retrieval.origin_id).entries.map { |entry| entry[:path] }, @intent.file
  end

  def test_capture_keeps_the_directory_on_disk
    capture.capture(@intent)

    assert File.directory?(folder.path(@intent.dir))
  end

  def test_an_intent_with_no_directory_is_refused_and_not_marked
    FileUtils.rm_rf(folder.path(@intent.dir))

    assert_equal "intent 1 has no directory to archive", assert_raises(Archive::Tree::Error) { capture.capture(@intent) }.message
    refute retrieval.archived?("1")
  end
end
