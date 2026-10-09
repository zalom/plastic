# frozen_string_literal: true

require_relative "../../test_helper"

class DeliveryHandoffTest < Plastic::TestCase
  include LifecycleHelper

  def active_intent
    intent = specified(records: nil)
    cli("intent", "approve", "1")
    cli("auto", "1")
    intent
  end

  def test_an_empty_graph_hands_planning_to_the_harness
    active_intent

    result = cli("intent", "brief", "1")

    assert_includes result.out, "plastic node add"
    assert_includes result.out, "next: none"
  end

  def test_a_done_graph_leads_to_explicit_intent_verification
    active_intent
    cli("node", "add", "1", "Ship", "--criterion", KEY)
    cli("node", "claim", "1", "n1")
    cli("node", "done", "1", "n1", "--findings", "Checked")

    result = cli("graph", "ready", "1")

    assert_includes result.out, "next: plastic intent end 1"
  end

  def test_the_handoff_texts_name_no_judge_option
    active_intent
    cli("node", "add", "1", "Ship", "--criterion", KEY)
    brief = cli("intent", "brief", "1").out
    claimed = cli("node", "claim", "1", "n1").out

    [brief, claimed].each { |text| refute_includes text, "--judge" }
    assert_includes claimed, "--findings"
  end
end
