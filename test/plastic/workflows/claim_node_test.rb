# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/claim_node"

class ClaimNodeTest < Plastic::TestCase
  def setup
    super
    open_intent
    store_graphs.work.add_node(intent_id: "1", title: "Build", criterion: "it runs", input: "spec.md")
  end

  def claim(id = "n1", intent_id: "1") = run_workflow(Plastic::Workflows::ClaimNode, harness: scoped_harness(session: "s-1"), intent_id:, id:)

  def test_a_claimed_node_prints_its_brief
    outcome, context = claim

    assert_equal [:done, ["node: n1 Build", "criterion: it runs", "input: spec.md"]], [outcome, context.printed]
    assert_equal "claimed", retrieval.node("1", "n1").state
  end

  def test_an_unknown_node_fails_the_call
    outcome, = claim("n9")

    assert_equal "code_claim_node, gate: no node n9 in intent 1", outcome.message
  end

  def test_a_node_waiting_on_an_open_node_is_blocked
    store_graphs.work.add_node(intent_id: "1", title: "Ship", criterion: "it ships")
    store_graphs.work.add_edge(intent_id: "1", from: "n1", to: "n2")

    outcome, = claim("n2")

    assert_match(/node n2 needs a node that is not done/, outcome.message)
    assert_equal "open", retrieval.node("1", "n2").state
  end

  def test_the_fourth_claim_is_refused_for_the_owner
    3.times do
      claim
      store_graphs.work.release_node(intent_id: "1", id: "n1")
    end

    outcome, = claim

    assert_equal [Plastic::Refused, "node n1 claimed 3 times; the owner decides"], [outcome.class, outcome.message]
  end

  def test_an_unknown_intent_fails_the_call
    assert_equal "code_claim_node, gate: no intent 9 in this store", claim(intent_id: "9").first.message
  end
end
