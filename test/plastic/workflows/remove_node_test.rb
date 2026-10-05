# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/remove_node"

class WorkflowRemoveNodeTest < Plastic::TestCase
  def setup
    super
    open_intent
    store_graphs.work.add_node(intent_id: "1", title: "Build", criterion: "it runs")
  end

  def remove = run_workflow(Plastic::Workflows::RemoveNode, intent_id: "1", id: "n1", reason: "not needed")

  def test_an_open_node_is_removed_with_its_reason
    outcome, context = remove

    assert_equal [:done, ["node: n1 removed"]], [outcome, context.printed]
    assert_equal ["removed", "not needed"], retrieval.node("1", "n1").to_h.values_at(:state, :reason)
  end

  def test_a_claimed_node_cannot_be_removed
    store_graphs.work.claim_node(intent_id: "1", id: "n1", by: "s-1")

    assert_equal "code_remove_node, gate: node n1 is claimed; it cannot move to removed", remove.first.message
  end
end
