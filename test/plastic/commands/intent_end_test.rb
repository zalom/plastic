# frozen_string_literal: true

require_relative "../../test_helper"
require "plastic/commands/intent_end"

class IntentEndTest < Plastic::TestCase
  include LifecycleHelper

  OUTCOME = "# Outcome\n\nDelivered and verified.\n\n## Verification\n"

  def finish(session: "delivery") = cli("intent", "end", "1", session:)

  def closed_intent
    accepted_intent
    review_off
    finish
  end

  %w[--judge --evidence].each do |option|
    define_method(:"test_#{option.delete("-")}_is_a_usage_error") do
      accepted_intent

      result = cli("intent", "end", "1", option, "x")

      assert_equal [2, "active"], [result.code, retrieval.intent("1").status]
    end
  end

  def test_abandoned_is_a_usage_error
    accepted_intent

    assert_equal [2, "active"], [cli("intent", "end", "1", "--abandoned").code, retrieval.intent("1").status]
  end

  def test_with_every_row_good_and_review_off_the_intent_closes_delivered_and_releases_the_lock
    accepted_intent(records: MERGE_RECORDS)
    review_off

    result = finish

    assert_equal 0, result.code
    assert_equal ["done", "delivered"], retrieval.intent("1").to_h.values_at(:status, :disposition)
    assert_nil retrieval.lock("1")
  end

  def test_the_completion_row_holds_the_verdict_judge_and_the_criteria
    closed_intent
    row = retrieval.completion("1")

    assert_equal "verdict", row.fetch("judge")
    assert_equal({ KEY => CRITERION }, JSON.parse(row.fetch("criteria")))
  end

  def test_the_completion_evidence_maps_each_key_to_node_ids_and_findings
    closed_intent
    evidence = JSON.parse(retrieval.completion("1").fetch("evidence"))

    assert_includes evidence.fetch(KEY).to_s, "n1"
    assert_includes evidence.fetch(KEY).to_s, "Acceptance passes for works"
  end

  def test_the_output_of_the_close_lists_the_printed_paths
    accepted_intent
    review_off

    result = finish

    assert_includes result.out, "printed store/1--alpha/graph.json"
  end

  def test_the_output_of_the_close_names_the_wind_down_step
    accepted_intent
    review_off

    assert_match(/stop/i, finish.out)
  end

  def test_a_second_end_exits_1_and_keeps_one_completion_row
    closed_intent

    result = finish

    assert_equal 1, result.code
    assert_equal 1, work_rows("completions").size
  end

  def test_a_live_foreign_lock_refuses_the_close
    accepted_intent
    review_off
    store_graphs.work.take_lock("1", session_id: "someone-else", mode: "auto")

    result = finish

    assert_equal [3, "active"], [result.code, retrieval.intent("1").status]
  end

  def test_with_no_verdict_the_handoff_names_the_judge_command
    specified
    delivered_nodes
    review_off

    result = finish

    assert_equal [0, "active"], [result.code, retrieval.intent("1").status]
    assert_includes result.out, "plastic intent judge 1"
  end

  def test_the_chain_has_no_problems
    assert_empty Plastic::Commands::IntentEnd.chain_problems
  end

  def test_a_missing_merge_record_hands_over_the_merge_check
    accepted_intent(records: "- Architecture map: enola at abc123\n")
    review_off

    result = finish

    assert_equal [0, "active"], [result.code, retrieval.intent("1").status]
    assert_includes result.out, "- Merged: "
    refute_match(/--judge|--evidence/, result.out)
  end
end

class IntentEndPullRequestTest < Plastic::TestCase
  include LifecycleHelper

  def finish = cli("intent", "end", "1")

  def test_required_without_a_pull_request_bullet_hands_over_the_record_step
    accepted_intent(records: MERGE_RECORDS)

    result = finish

    assert_equal [0, "active"], [result.code, retrieval.intent("1").status]
    assert_includes result.out, "Pull request:"
  end

  def test_required_with_a_pull_request_and_no_approval_waits_for_the_person
    accepted_intent(records: MERGE_RECORDS + PULL_REQUEST)

    result = finish

    assert_equal [3, "active"], [result.code, retrieval.intent("1").status]
    assert_match(/approval/i, result.err + result.out)
  end

  def test_required_with_no_verdict_and_no_pull_request_lists_both
    specified(records: MERGE_RECORDS)
    delivered_nodes

    result = finish

    assert_equal [0, "active"], [result.code, retrieval.intent("1").status]
    assert_includes result.out, "plastic intent judge 1"
    assert_includes result.out, "Pull request:"
  end

  def test_required_with_the_approval_closes
    accepted_intent

    assert_equal [0, "done"], [finish.code, retrieval.intent("1").status]
  end

  def test_off_closes_with_no_pull_request_bullets
    accepted_intent(records: MERGE_RECORDS)
    review_off

    assert_equal [0, "done"], [finish.code, retrieval.intent("1").status]
  end
end
