# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/park_node"

class WorkflowParkNodeTest < Plastic::TestCase
  def setup
    super
    open_intent
    store_graphs.work.add_node(intent_id: "1", title: "Build", criterion: "it runs")
  end

  def park = run_workflow(Plastic::Workflows::ParkNode, intent_id: "1", id: "n1", question: "which way?")

  def test_a_claimed_node_is_parked_with_its_question
    store_graphs.work.claim_node(intent_id: "1", id: "n1", by: "s-1")

    outcome, context = park

    assert_equal "plastic node answer 1 n1 --answer TEXT", Plastic::Workflows::ParkNode.closing(outcome, context).first
    assert_equal ["parked", "which way?"], retrieval.node("1", "n1").to_h.values_at(:state, :question)
  end

  def test_an_open_node_cannot_be_parked
    assert_equal "code_park_node, gate: node n1 is open; it cannot move to parked", park.first.message
  end
end
