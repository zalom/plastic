# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/remove_edge"

class WorkflowRemoveEdgeTest < Plastic::TestCase
  def setup
    super
    open_intent
    work = store_graphs.work
    work.add_node(intent_id: "1", title: "Build")
    work.add_node(intent_id: "1", title: "Ship")
    work.add_edge(intent_id: "1", from: "n1", to: "n2")
  end

  def remove(from) = run_workflow(Plastic::Workflows::RemoveEdge, intent_id: "1", from:, to: "n2")

  def test_an_edge_is_removed_and_named
    outcome, context = remove("n1")

    assert_equal [:done, ["edge: n1 to n2 removed"]], [outcome, context.printed]
    assert_empty retrieval.edges("1")
  end

  def test_a_missing_edge_fails_and_keeps_the_others
    outcome, = remove("n9")

    assert_equal "code_remove_edge, gate: no edge n9 to n2 in intent 1", outcome.message
    assert_equal 1, retrieval.edges("1").size
  end

  def test_a_failed_removal_is_tried_again_on_the_next_call
    _outcome, context = remove("n9")
    context[:from] = "n1"

    assert_equal :done, Plastic::Workflows::RemoveEdge.call(context)
  end
end
