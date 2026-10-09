# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/ask_node"

class WorkflowAskNodeTest < Plastic::TestCase
  def setup
    super
    open_intent
    store_graphs.work.add_node(intent_id: "1", title: "Build", criterion: "it runs")
  end

  def ask = run_workflow(Plastic::Workflows::AskNode, intent_id: "1", id: "n1", text: "which way?")

  def test_a_claimed_node_needs_info_with_its_question
    store_graphs.work.claim_node(intent_id: "1", id: "n1", by: "s-1")

    outcome, context = ask

    assert_equal "plastic node resolve 1 n1 TEXT", Plastic::Workflows::AskNode.closing(outcome, context).first
    assert_equal ["needs_info", "which way?"], retrieval.node("1", "n1").to_h.values_at(:state, :question)
  end

  def test_an_open_node_cannot_be_asked_about
    assert_equal "code_ask_node, gate: node n1 is open; it cannot move to needs_info", ask.first.message
  end
end
