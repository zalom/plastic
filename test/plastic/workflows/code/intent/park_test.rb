# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/workflows/code/intent/park"

class WorkflowParkIntentTest < Plastic::TestCase
  def session_graphs = Plastic::Graph.open(home: @plastic_home, store: "global", session: "s-1")

  def park(intent_id = "1", reason: "waits on review") = run_workflow(Plastic::Workflows::Code::Intent::Park, graphs: session_graphs, intent_id:, reason:)

  def kinds = retrieval.structure.work_log("1").map(&:kind)

  def started_intent
    open_intent
    store_graphs.work.activate_intent("1")
  end

  def test_an_intent_in_progress_is_parked_with_its_reason
    started_intent

    outcome, = park

    assert_equal [:done, "parked", "waits on review"], [outcome, *retrieval.intent("1").to_h.values_at(:status, :reason)]
  end

  def test_parking_writes_one_parked_line
    started_intent

    park

    assert_equal 1, kinds.count("parked")
  end

  def test_a_rerun_on_a_parked_intent_fails_and_writes_no_second_line
    started_intent
    park

    error = assert_raises(Plastic::Failed) { park(reason: "second") }

    assert_equal ["intent 1 is parked; only an intent in progress parks", 1, "waits on review"],
      [error.message, kinds.count("parked"), retrieval.intent("1").reason]
  end

  def test_an_intent_that_is_not_in_progress_fails_and_stays_as_it_was
    open_intent

    error = assert_raises(Plastic::Failed) { park }

    assert_equal ["intent 1 is open; only an intent in progress parks", "open", []], [error.message, retrieval.intent("1").status, kinds - ["opened"]]
  end

  def test_an_unknown_intent_fails_the_call
    assert_equal "no intent 9 in this store", assert_raises(Plastic::Failed) { park("9") }.message
  end
end
