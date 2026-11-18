# frozen_string_literal: true

require_relative "../../../test_helper"

class KnowledgeStorePathTest < Plastic::TestCase
  StorePath = Plastic::Graph::Knowledge::StorePath

  def test_the_context_file_of_an_intent_folder_is_a_generated_view
    assert StorePath.context_view?("store/1--alpha/context.json")
    refute StorePath.context_view?("store/1--alpha/graph.json")
    refute StorePath.context_view?("store/1--alpha/notes.json")
  end

  def test_a_roadmap_log_sits_beside_its_roadmap
    assert_equal ["roadmaps/a.savepoint.md", true, false], [StorePath.roadmap_log("roadmaps/a.md"), StorePath.roadmap_log?("roadmaps/a.savepoint.md"), StorePath.roadmap_log?("roadmaps/a.md")]
  end

  def test_a_roadmap_and_a_graph_file_are_told_by_their_path
    assert_equal [true, false, true, false], [StorePath.roadmap?("roadmaps/a.md"), StorePath.roadmap?("store/1--a/spec.md"), StorePath.graph_file?("store/1--a/graph.json"), StorePath.graph_file?("store/1--a/context.json")]
  end
end
