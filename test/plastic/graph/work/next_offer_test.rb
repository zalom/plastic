# frozen_string_literal: true

require_relative "../../../test_helper"

class WorkNextOfferTest < Plastic::TestCase
  def offer
    pick = Plastic::Graph::Work::NextPick.new(retrieval, "s-1")
    Plastic::Graph::Work::NextOffer.new(retrieval, pick).call
  end

  def test_nothing_open_offers_none_with_no_handoff
    assert_equal ["none", "nothing is open", nil], offer
  end

  def test_an_intent_with_no_done_criteria_offers_the_spec
    open_intent

    assert_equal ["plastic intent spec 1", "intent 1 has no done criteria", nil], offer
  end

  def test_several_candidates_hand_the_choice_to_the_agent
    open_intent("Alpha")
    open_intent("Beta")

    command, why, handoff = offer

    assert_nil command
    assert_equal "choose the intent to work on", why
    assert_includes handoff, "plastic status"
  end
end
