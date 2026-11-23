# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/work/next_pick"
require_relative "../../../../lib/plastic/graph/work/next_offer"

class WorkNextOfferTest < Plastic::TestCase
  def offer
    pick = Plastic::Graph::Work::NextPick.new(retrieval, "s-1", now: Time.now)
    Plastic::Graph::Work::NextOffer.new(retrieval, pick).call
  end

  def test_nothing_open_offers_no_command_with_no_handoff
    assert_equal [nil, "nothing is open", nil], offer
  end

  def test_an_intent_with_no_done_criteria_offers_the_spec
    open_intent

    assert_equal ["plastic intent spec 1", "intent 1 has no done criteria", nil], offer
  end

  def test_an_approved_open_intent_with_no_done_criteria_offers_intent_start_before_the_spec
    open_intent
    store_graphs.work.approve_intent("1")

    assert_equal ["plastic intent start 1", "intent 1 is open", nil], offer
  end

  def test_several_candidates_hand_the_choice_to_the_agent
    open_intent("Alpha")
    open_intent("Beta")

    command, why, handoff = offer

    assert_nil command
    assert_equal "choose the intent to work on", why
    assert_includes handoff, "plastic status"
  end

  Approvals = Data.define(:approved) do
    def approval(_id) = approved
  end
  Reads = Data.define(:structure)

  def go_ahead(approved) = Plastic::Graph::Work::NextOffer.go_ahead_offer(Reads.new(Approvals.new(approved)), "1")

  def test_an_approved_open_intent_offers_intent_start
    assert_equal ["plastic intent start 1", "intent 1 is open", nil], go_ahead(true)
  end

  def test_an_open_intent_before_the_go_ahead_hands_the_owner_the_approve_command
    command, why, handoff = go_ahead(nil)

    assert_nil command
    assert_equal "the owner must give the go-ahead for intent 1", why
    assert_includes handoff, "plastic intent approve 1"
  end
end

class WorkBlockedOfferTest < Plastic::TestCase
  def offer
    pick = Plastic::Graph::Work::NextPick.new(retrieval, "s-1", now: Time.now)
    Plastic::Graph::Work::NextOffer.new(retrieval, pick).call
  end

  def test_when_every_open_intent_waits_the_offer_names_what_it_waits_on
    open_intent("Alpha")
    open_intent("Beta", status: "parked")
    store_graphs.work.add_link(from_ref: "1", to_ref: "2", kind: "needs")

    assert_equal [nil, "nothing is ready: intent 1 waits on intent 2", nil], offer
  end

  def test_a_ready_intent_is_offered_while_another_waits
    open_intent("Alpha")
    open_intent("Beta")
    store_graphs.work.add_link(from_ref: "1", to_ref: "2", kind: "needs")

    assert_equal ["plastic intent spec 2", "intent 2 has no done criteria", nil], offer
  end
end

class WorkFutureOfferTest < Plastic::TestCase
  def offer
    pick = Plastic::Graph::Work::NextPick.new(retrieval, "s-1", now: Time.now)
    Plastic::Graph::Work::NextOffer.new(retrieval, pick).call
  end

  def test_an_approved_future_intent_offers_intent_start_naming_its_status
    open_intent("Alpha", status: "future")
    store_graphs.work.approve_intent("1")

    assert_equal ["plastic intent start 1", "intent 1 is future", nil], offer
  end

  def test_only_blocked_future_intents_name_what_the_first_waits_on
    open_intent("Alpha", status: "future")
    open_intent("Beta", status: "parked")
    store_graphs.work.add_link(from_ref: "1", to_ref: "2", kind: "needs")

    assert_equal [nil, "nothing is ready: intent 1 waits on intent 2", nil], offer
  end
end
