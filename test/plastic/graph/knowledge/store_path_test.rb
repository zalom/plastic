# frozen_string_literal: true

require_relative "../../../test_helper"

class KnowledgeStorePathTest < Plastic::TestCase
  StorePath = Plastic::Graph::Knowledge::StorePath

  def test_the_context_file_of_an_intent_folder_is_a_generated_view
    assert StorePath.context_view?("store/1--alpha/context.json")
    refute StorePath.context_view?("store/1--alpha/graph.json")
    refute StorePath.context_view?("store/1--alpha/notes.json")
  end

  def test_a_graph_file_is_told_by_its_path
    assert_equal [true, false], [StorePath.graph_file?("store/1--a/graph.json"), StorePath.graph_file?("store/1--a/context.json")]
  end
end
