# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/answer_node"

class WorkflowAnswerNodeTest < Plastic::TestCase
  def setup
    super
    open_intent
    store_graphs.work.add_node(intent_id: "1", title: "Build", criterion: "it runs")
  end

  def answer = run_workflow(Plastic::Workflows::AnswerNode, intent_id: "1", id: "n1", answer: "left").first

  def test_a_parked_node_is_answered_and_its_retries_reset
    store_graphs.work.claim_node(intent_id: "1", id: "n1", by: "s-1")
    store_graphs.work.park_node(intent_id: "1", id: "n1", question: "which way?")

    outcome = answer

    assert_equal [:done, "open", "left", 0], [outcome, *retrieval.node("1", "n1").to_h.values_at(:state, :answer, :retries)]
  end

  def test_an_open_node_cannot_be_answered
    assert_equal "code_answer_node, gate: node n1 is open; it cannot move to open", answer.message
  end
end
