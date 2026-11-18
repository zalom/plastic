# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/workflows/code/auto"

class WorkflowStartAutoTest < Plastic::TestCase
  include DeliveryHelper

  def start(session: "s-1", intent_id: "1")
    run_workflow(Plastic::Workflows::Code::Auto, harness: scoped_harness(session:), graphs: session_graphs, intent_id:).first
  end

  def approve(intent_id = "1") = plastic("intent", "approve", intent_id, table: Plastic::CLI::TABLE)

  def test_a_specified_intent_goes_active
    specified_intent
    approve

    outcome = start

    assert_equal [:done, "in_progress"], [outcome, retrieval.intent("1").status]
  end

  def test_an_open_decision_is_refused
    specified_intent("## Open decisions\n- Which way\n\n## Done criteria\n- It works\n")

    assert_equal "intent 1 has an open decision; run plastic intent spec 1", assert_raises(Plastic::Refused) { start }.message
  end

  def test_a_spec_without_criteria_is_refused
    specified_intent("## Goal\n- Ship\n")

    error = assert_raises(Plastic::Failed) { start }
    assert_includes error.message, "intent 1 names no done criterion"
  end

  def test_a_done_intent_is_refused
    open_intent(status: "done")

    error = assert_raises(Plastic::Failed) { start }
    assert_includes error.message, "intent 1 is done"
  end

  def test_a_call_with_no_session_fails
    specified_intent

    assert_equal "auto names no session; set PLASTIC_SESSION", assert_raises(Plastic::Failed) { start(session: nil) }.message
  end

  def test_an_unknown_intent_fails
    assert_equal "no intent 9 in this store", assert_raises(Plastic::Failed) { start(intent_id: "9") }.message
  end

  def test_an_intent_without_a_go_ahead_is_refused_naming_the_approve_command
    specified_intent

    error = assert_raises(Plastic::Refused) { start }

    assert_includes error.message, "plastic intent approve 1"
    assert_equal "open", retrieval.intent("1").status
  end

  def test_an_intent_with_a_go_ahead_starts
    specified_intent
    approve

    assert_equal :done, start
  end
end
