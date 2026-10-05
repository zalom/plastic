# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/pick_next"

class PickNextTest < Plastic::TestCase
  include DeliveryHelper

  def pick
    outcome, context = run_workflow(Plastic::Workflows::PickNext, harness: scoped_harness(session: "s-1"))
    [outcome, context.next_command, context.why]
  end

  def test_nothing_open_offers_none
    assert_equal [:done, "none", "nothing is open"], pick
  end

  def test_an_intent_without_criteria_offers_its_spec
    open_intent

    assert_equal [:done, "plastic intent spec 1", "intent 1 has no done criteria"], pick
  end

  def test_an_open_decision_offers_the_spec
    specified_intent("## Open decisions\n- Which way\n\n## Done criteria\n- It works\n")

    assert_equal "intent 1 has an open decision", pick.last
  end

  def test_a_specified_open_intent_offers_the_start
    specified_intent

    assert_equal [:done, "plastic auto start 1", "intent 1 is open"], pick
  end

  def test_an_active_intent_offers_its_next_node
    specified_intent
    store_graphs.work.activate_intent("1")
    store_graphs.work.add_node(intent_id: "1", title: "Build")

    assert_equal [:done, "plastic node claim 1 n1", "node n1 is ready"], pick
  end

  def test_two_open_intents_hand_the_choice_to_the_agent
    open_intent
    open_intent("Beta")

    assert_equal [:agent_needed, nil, "choose the intent to work on"], pick
  end
end
