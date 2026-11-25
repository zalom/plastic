# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/workflows/code/node/release"

class MoveNodeTest < Plastic::TestCase
  def setup
    super
    open_intent
    store_graphs.work.add_node(intent_id: "1", title: "Build", criterion: "it runs")
  end

  def release(id: "n1", intent_id: "1") = run_workflow(Plastic::Workflows::Code::Node::Release, intent_id:, id:)

  def test_an_unknown_intent_fails_before_any_move
    assert_equal "no intent 9 in this store", assert_raises(Plastic::Failed) { release(intent_id: "9") }.message
  end

  def test_an_unknown_node_is_named_in_the_failure
    assert_equal "no node n9 in intent 1", assert_raises(Plastic::Failed) { release(id: "n9") }.message
  end

  def test_a_refused_move_is_tried_again_on_the_next_call
    context = stop_workflow(Plastic::Workflows::Code::Node::Release, Plastic::Refused, intent_id: "1", id: "n1").last
    store_graphs.work.claim_node(intent_id: "1", id: "n1", by: "s-1")

    outcome = Plastic::Workflows::Code::Node::Release.call(context)

    assert_equal [:done, "open"], [outcome, retrieval.node("1", "n1").state]
  end

  def release_as(session) = stop_workflow(Plastic::Workflows::Code::Node::Release, Plastic::Refused, harness: scoped_harness(session:), intent_id: "1", id: "n1").first

  def test_a_node_held_by_another_session_is_refused_as_taken
    store_graphs.work.claim_node(intent_id: "1", id: "n1", by: "s-1")

    assert_equal "node n1 is held by session s-1; its claim was taken", release_as("s-2").message
    assert_equal "claimed", retrieval.node("1", "n1").state
  end

  def test_a_node_finished_by_another_session_is_refused_as_taken
    store_graphs.work.claim_node(intent_id: "1", id: "n1", by: "s-1")
    store_graphs.work.done_node(intent_id: "1", id: "n1", by: "s-1", output: "built")

    assert_equal "node n1 is held by session s-1; its claim was taken", release_as("s-2").message
  end
end
