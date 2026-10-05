# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../scripts/lib/plastic/graph/knowledge/archive/writer"

class KnowledgeArchiveSnapshotIndexTest < Plastic::TestCase
  def index(entries)
    graphs = store_graphs
    Plastic::Graph::Knowledge::Archive::SnapshotIndex.new(graphs.databases[:knowledge], graphs.retrieval.origin_id).index("1", entries)
  end

  def entry(path, kind: "file", data: "# Notes\n") = { path:, kind:, data: data&.b }

  def test_each_text_file_becomes_a_document_of_the_intent
    index([entry("notes.md")])

    assert_equal [["notes.md", "# Notes\n"]], retrieval.documents("1").map { |document| [document.path, document.body] }
  end

  def test_folders_links_and_binary_files_are_left_out
    index([entry("", kind: "directory", data: nil), entry("link", kind: "link", data: "/x"), entry("image.png", data: "\x89PNG\x00\x01")])

    assert_empty retrieval.documents("1")
  end
end
