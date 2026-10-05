# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/remove_roadmap_edge"

class WorkflowRemoveRoadmapEdgeTest < Plastic::TestCase
  include RoadmapHelper

  def setup
    super
    roadmap
    item("a")
    item("b", after: ["a"])
  end

  def remove(from) = run_workflow(Plastic::Workflows::RemoveRoadmapEdge, slug: "r1", from:, to: "b")

  def test_an_edge_is_removed_and_named
    outcome, context = remove("a")

    assert_equal [:done, ["edge: a to b removed"]], [outcome, context.printed]
    assert_empty retrieval.roadmap_edges("r1")
  end

  def test_a_missing_edge_fails_and_keeps_the_others
    outcome, = remove("z")

    assert_equal "code_remove_roadmap_edge, gate: no edge z to b on roadmap r1", outcome.message
    assert_equal 1, retrieval.roadmap_edges("r1").size
  end
end
