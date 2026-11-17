# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/work/next_pick"

class WorkNextPickTest < Plastic::TestCase
  def test_two_open_intents_pick_none
    open_intent("Alpha")
    open_intent("Beta")

    assert_nil Plastic::Graph::Work::NextPick.new(store_graphs.retrieval, "s-1", now: Time.now).intent
  end
end

class WorkInProgressPickTest < Plastic::TestCase
  def test_an_in_progress_intent_is_picked_before_an_open_one
    open_intent("Alpha")
    open_intent("Beta", status: "in_progress")
    open_intent("Gamma")

    assert_equal "2", Plastic::Graph::Work::NextPick.new(retrieval, "s-1", now: Time.now).intent.intent_id
  end
end

class WorkClosedIntentPickTest < Plastic::TestCase
  def test_a_closed_intent_is_not_selected_through_a_leftover_claim
    intent = open_intent(status: "done")
    store_graphs.work.add_node(intent_id: intent.intent_id, title: "Build")
    store_graphs.work.claim_node(intent_id: intent.intent_id, id: "n1", by: "s-1")

    assert_nil Plastic::Graph::Work::NextPick.new(retrieval, "s-1", now: Time.now).intent
  end
end
