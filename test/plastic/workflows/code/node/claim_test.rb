# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/workflows/code/node/claim"

class ClaimNodeTest < Plastic::TestCase
  def setup
    super
    intent = open_intent
    write("#{intent.dir}/spec.md", "## Done criteria\n- It works\n")
    sync_up
    store_graphs.work.approve_intent("1")
    store_graphs.work.activate_intent("1")
    store_graphs.work.add_node(intent_id: "1", title: "Build", criterion: "it runs", inputs: ["spec.md", "notes.md"])
  end

  def claim(id = "n1", intent_id: "1") = run_workflow(Plastic::Workflows::Code::Node::Claim, harness: scoped_harness(session: "s-1"), intent_id:, id:, agent: "")

  def test_a_claimed_node_prints_its_brief
    outcome, context = claim

    assert_equal [:done, ["node: n1 Build", "criterion: it runs", "criterion text: it runs", "input: spec.md", "input: notes.md", "output: a JSON file, given with plastic node done 1 n1 TEXT --output PATH"]], [outcome, context.printed]
    assert_equal "claimed", retrieval.node("1", "n1").state
  end

  def test_an_unknown_node_fails_the_call
    error = assert_raises(Plastic::Failed) { claim("n9") }

    assert_equal "no node n9 in intent 1", error.message
  end

  def test_a_node_waiting_on_an_open_node_is_blocked
    store_graphs.work.add_node(intent_id: "1", title: "Ship", criterion: "it ships")
    store_graphs.work.add_edge(intent_id: "1", from: "n1", to: "n2")

    error = assert_raises(Plastic::Refused) { claim("n2") }

    assert_match(/node n2 needs a node that is not done/, error.message)
    assert_equal "open", retrieval.node("1", "n2").state
  end

  def test_the_fourth_claim_is_refused_for_the_owner
    3.times do
      claim
      store_graphs.work.release_node(intent_id: "1", id: "n1")
    end

    error = assert_raises(Plastic::Refused) { claim }

    assert_equal [Plastic::Refused, "node n1 claimed 3 times; the owner decides"], [error.class, error.message]
  end

  def test_an_unknown_intent_fails_the_call
    assert_equal "no intent 9 in this store", assert_raises(Plastic::Failed) { claim(intent_id: "9") }.message
  end
end
