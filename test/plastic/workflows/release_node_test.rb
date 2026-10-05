# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/release_node"

class WorkflowReleaseNodeTest < Plastic::TestCase
  def setup
    super
    open_intent
    store_graphs.work.add_node(intent_id: "1", title: "Build", criterion: "it runs")
  end

  def release = run_workflow(Plastic::Workflows::ReleaseNode, intent_id: "1", id: "n1")

  def test_a_claimed_node_is_released_and_offers_the_next_claim
    store_graphs.work.claim_node(intent_id: "1", id: "n1", by: "s-1")

    outcome, context = release

    assert_equal ["plastic node claim 1 n1", "node n1 is open"], Plastic::Workflows::ReleaseNode.closing(outcome, context)
    assert_equal "open", retrieval.node("1", "n1").state
  end

  def test_an_open_node_is_refused_with_its_state
    assert_equal "code_release_node, gate: node n1 is open; it cannot move to open", release.first.message
  end
end
