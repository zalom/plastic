# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/resolve_node"

class WorkflowResolveNodeTest < Plastic::TestCase
  def setup
    super
    open_intent
    store_graphs.work.add_node(intent_id: "1", title: "Build", criterion: "it runs")
  end

  def resolve = run_workflow(Plastic::Workflows::ResolveNode, intent_id: "1", id: "n1", text: "left").first

  def test_a_needs_info_node_is_resolved_and_its_retries_reset
    store_graphs.work.claim_node(intent_id: "1", id: "n1", by: "s-1")
    store_graphs.work.ask_node(intent_id: "1", id: "n1", question: "which way?")

    outcome = resolve

    assert_equal [:done, "open", "left", 0], [outcome, *retrieval.node("1", "n1").to_h.values_at(:state, :answer, :retries)]
  end

  def test_an_open_node_cannot_be_resolved
    assert_equal "code_resolve_node, gate: node n1 is open; it cannot move to open", resolve.message
  end
end
