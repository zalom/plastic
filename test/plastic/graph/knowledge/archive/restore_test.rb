# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../scripts/lib/plastic/graph/knowledge/archive/writer"

class KnowledgeArchiveRestoreTest < Plastic::TestCase
  Archive = Plastic::Graph::Knowledge::Archive

  def setup
    super
    @intent = open_intent("Target", status: "future")
    @graphs = store_graphs
  end

  def writer = Archive::Writer.new(@graphs.databases, @graphs.retrieval, folder)

  def snapshot(intent_id) = Archive::Snapshot.new(@graphs.databases[:work], intent_id, @graphs.retrieval.origin_id)

  def restore = Archive::Restore.new(@graphs.databases[:work], @graphs.retrieval, folder, snapshot: method(:snapshot))

  def test_restoring_an_archived_intent_writes_its_folder_back_and_clears_the_marker
    writer.archive("1")

    assert_equal [true, nil, nil], restore.call("1")
    assert_path_exists folder.path("#{@intent.dir}/#{@intent.file}")
    refute retrieval.archived?("1")
  end

  def test_an_intent_that_is_not_archived_fails
    assert_equal [false, "intent 1 is not archived", :failure], restore.call("1")
  end
end
