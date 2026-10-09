# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/fail_node"

class WorkflowFailNodeTest < Plastic::TestCase
  def setup
    super
    open_intent
    store_graphs.work.add_node(intent_id: "1", title: "Build", criterion: "it runs")
  end

  def fail_node = run_workflow(Plastic::Workflows::FailNode, intent_id: "1", id: "n1", text: "red")

  def test_a_claimed_node_fails_with_its_reason
    store_graphs.work.claim_node(intent_id: "1", id: "n1", by: "s-1")

    outcome, context = fail_node

    assert_equal ["plastic node release 1 n1", "node n1 is failed"], Plastic::Workflows::FailNode.closing(outcome, context)
    assert_equal %w[failed red], retrieval.node("1", "n1").to_h.values_at(:state, :reason)
  end

  def test_an_open_node_cannot_fail
    assert_equal "code_fail_node, gate: node n1 is open; it cannot move to failed", fail_node.first.message
  end
end
