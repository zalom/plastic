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

class WorkReadyIntentPickTest < Plastic::TestCase
  def pick = Plastic::Graph::Work::NextPick.new(retrieval, "s-1", now: Time.now)

  def need(from, to) = store_graphs.work.add_link(from_ref: from, to_ref: to, kind: "needs")

  def test_an_open_intent_that_needs_an_open_intent_is_not_picked_and_the_needed_one_is
    open_intent("Alpha")
    open_intent("Beta")
    need("1", "2")

    assert_equal "2", pick.intent.intent_id
  end

  def test_an_open_intent_whose_needed_intent_is_done_is_ready
    open_intent("Alpha")
    open_intent("Beta", status: "done")
    need("1", "2")

    assert_equal "1", pick.intent.intent_id
  end

  def test_an_open_intent_whose_needed_intent_is_abandoned_is_ready
    open_intent("Alpha")
    open_intent("Beta", status: "abandoned")
    need("1", "2")

    assert_equal "1", pick.intent.intent_id
  end

  def test_an_open_intent_waiting_on_a_parked_intent_leaves_nothing_to_pick
    open_intent("Alpha")
    open_intent("Beta", status: "parked")
    need("1", "2")

    assert_predicate pick, :none?
  end

  def test_the_intents_a_blocked_intent_waits_on_are_named
    open_intent("Alpha")
    open_intent("Beta", status: "parked")
    need("1", "2")

    assert_equal({ "1" => ["2"] }, pick.blocked)
  end
end
