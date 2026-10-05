# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/release_node"

class MoveNodeTest < Plastic::TestCase
  def setup
    super
    open_intent
    store_graphs.work.add_node(intent_id: "1", title: "Build", criterion: "it runs")
  end

  def release(id: "n1", intent_id: "1") = run_workflow(Plastic::Workflows::ReleaseNode, intent_id:, id:)

  def test_an_unknown_intent_fails_before_any_move
    assert_equal "code_release_node, gate: no intent 9 in this store", release(intent_id: "9").first.message
  end

  def test_an_unknown_node_is_named_in_the_failure
    assert_equal "code_release_node, gate: no node n9 in intent 1", release(id: "n9").first.message
  end

  def test_a_refused_move_is_tried_again_on_the_next_call
    _outcome, context = release
    store_graphs.work.claim_node(intent_id: "1", id: "n1", by: "s-1")

    outcome = Plastic::Workflows::ReleaseNode.call(context)

    assert_equal [:done, "open"], [outcome, retrieval.node("1", "n1").state]
  end
end
