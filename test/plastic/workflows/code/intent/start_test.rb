# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/workflows/code/intent/start"

class WorkflowStartIntentTest < Plastic::TestCase
  include DeliveryHelper

  def start(session: "s-1", intent_id: "1")
    run_workflow(Plastic::Workflows::Code::Intent::Start, harness: scoped_harness(session:), graphs: session_graphs, intent_id:,
      start_words: "intent start").first
  end

  def approve(intent_id = "1") = plastic("intent", "approve", intent_id, table: Plastic::CLI::TABLE)

  def tables = store_graphs.databases.fetch(:local).rows("SELECT name FROM sqlite_master WHERE type = 'table'").map { |row| row["name"] }

  def test_a_specified_intent_with_a_go_ahead_goes_in_progress
    specified_intent
    approve

    assert_equal [:done, "in_progress"], [start, retrieval.intent("1").status]
  end

  def test_an_open_decision_goes_in_progress_and_offers_the_spec
    specified_intent("## Open decisions\n- Which way\n\n## Done criteria\n- It works\n")
    approve

    assert_equal [:unsettled, "in_progress"], [start, retrieval.intent("1").status]
  end

  def test_a_spec_without_criteria_goes_in_progress_and_offers_the_spec
    specified_intent("## Goal\n- Ship\n")
    approve

    assert_equal [:unsettled, "in_progress"], [start, retrieval.intent("1").status]
  end

  def test_an_intent_without_a_go_ahead_goes_in_progress_and_offers_the_spec
    specified_intent

    assert_equal [:unsettled, "in_progress"], [start, retrieval.intent("1").status]
  end

  def test_a_done_intent_fails
    open_intent(status: "done")

    error = assert_raises(Plastic::Failed) { start }
    assert_includes error.message, "intent 1 is done"
  end

  def test_a_call_with_no_session_fails_and_names_the_command
    specified_intent

    assert_equal "intent start names no session; set PLASTIC_SESSION", assert_raises(Plastic::Failed) { start(session: nil) }.message
  end

  def test_an_unknown_intent_fails
    assert_equal "no intent 9 in this store", assert_raises(Plastic::Failed) { start(intent_id: "9") }.message
  end

  def test_the_intent_goes_in_progress_and_no_lock_row_or_table_exists
    specified_intent
    approve

    assert_equal [:done, "in_progress"], [start, retrieval.intent("1").status]
    refute_includes tables, "locks"
  end

  def test_another_session_holding_a_node_does_not_stop_the_start
    specified_intent
    approve
    store_graphs.work.add_node(intent_id: "1", title: "Build", criterion: "it works")
    store_graphs.work.claim_node(intent_id: "1", id: "n1", by: "s-2")

    assert_equal :done, start
  end
end
