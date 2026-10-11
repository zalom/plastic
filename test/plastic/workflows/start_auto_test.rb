# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/start_auto"

class WorkflowStartAutoTest < Plastic::TestCase
  include DeliveryHelper

  def start(session: "s-1", intent_id: "1")
    run_workflow(Plastic::Workflows::StartAuto, harness: scoped_harness(session:), graphs: session_graphs, intent_id:).first
  end

  def approve(intent_id = "1") = plastic("intent", "approve", intent_id, table: Plastic::CLI::TABLE)

  def test_a_specified_intent_goes_active_under_this_session_lock
    specified_intent
    approve

    outcome = start

    assert_equal [:done, "active"], [outcome, retrieval.intent("1").status]
    assert_equal %w[s-1 auto], retrieval.lock("1").to_h.values_at(:session_id, :mode)
  end

  def test_an_open_decision_is_refused
    specified_intent("## Open decisions\n- Which way\n\n## Done criteria\n- It works\n")

    assert_equal "intent 1 has an open decision; run plastic intent spec 1", start.message
  end

  def test_a_spec_without_criteria_is_refused
    specified_intent("## Goal\n- Ship\n")

    assert_kind_of Plastic::Failed, start
    assert_includes start.message, "intent 1 names no done criterion"
  end

  def test_a_done_intent_is_refused
    open_intent(status: "done")

    assert_kind_of Plastic::Failed, start
    assert_includes start.message, "intent 1 is done"
  end

  def test_another_live_session_lock_is_refused_and_kept
    specified_intent
    store_graphs.work.take_lock("1", session_id: "s-2", mode: "auto")

    assert_equal "intent 1 is locked by session s-2", start.message
    assert_equal "s-2", retrieval.lock("1").session_id
  end

  def test_a_call_with_no_session_fails
    specified_intent

    assert_equal "code_start_auto, gate: plastic auto names no session", start(session: nil).message
  end

  def test_an_unknown_intent_fails
    assert_equal "code_start_auto, gate: no intent 9 in this store", start(intent_id: "9").message
  end

  def test_an_intent_without_a_go_ahead_is_refused_naming_the_approve_command_and_takes_no_lock
    specified_intent

    outcome = start

    assert_kind_of Plastic::Refused, outcome
    assert_includes outcome.message, "plastic intent approve 1"
    assert_equal [nil, "open"], [retrieval.lock("1"), retrieval.intent("1").status]
  end

  def test_an_active_intent_with_no_lock_takes_the_lock
    specified_intent
    approve
    store_graphs.work.activate_intent("1")

    assert_equal [:done, "s-1"], [start, retrieval.lock("1")&.session_id]
  end

  def test_an_intent_with_a_go_ahead_starts
    specified_intent
    approve

    assert_equal :done, start
  end
end
