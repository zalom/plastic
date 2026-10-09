# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/prepare_ending"

class PrepareEndingFixture < Plastic::TestCase
  include LifecycleHelper

  def prepare(session: "delivery")
    run_workflow(Plastic::Workflows::PrepareEnding, harness: scoped_harness(session:), graphs: session_graphs(session), intent_id: "1")
  end

  def session_graphs(session) = Plastic::Graph.open(home: @plastic_home, store: "global", session:)
end

class PrepareEndingTest < PrepareEndingFixture
  def test_an_accepted_delivered_intent_is_ready_to_end
    accepted_intent

    assert_equal :ready, prepare.first
  end

  def test_no_verdict_row_hands_over_to_the_agent
    specified
    delivered_nodes

    assert_equal :agent_needed, prepare.first
  end

  def test_a_latest_verdict_of_revise_is_not_ready
    specified
    delivered_nodes
    set_node_times(EARLY)
    put_verdict(1, "revise", LATE)

    refute_equal :ready, prepare.first
  end

  def test_an_accept_older_than_a_live_node_is_not_ready
    specified
    delivered_nodes
    put_verdict(1, "accept", EARLY)
    set_node_times(LATE)

    refute_equal :ready, prepare.first
  end

  def test_an_accept_at_the_same_second_as_the_node_is_ready
    specified
    delivered_nodes
    put_verdict(1, "accept", MIDDLE)
    set_node_times(MIDDLE)

    assert_equal :ready, prepare.first
  end

  def test_the_same_instant_written_with_another_offset_is_ready
    specified
    delivered_nodes
    put_verdict(1, "accept", "2026-10-05T09:00:00Z")
    set_node_times("2026-10-05T11:00:00+02:00")

    assert_equal :ready, prepare.first
  end

  def test_a_removed_node_does_not_age_the_verdict
    accepted_intent
    cli("node", "add", "1", "Extra", "--criterion", KEY)
    cli("node", "remove", "1", "n2")
    store_graphs.databases.fetch(:work).transaction { |batch| batch.add("UPDATE nodes SET updated_at = :at WHERE id = 'n2'", at: "2026-10-06T10:00:00+02:00") }

    assert_equal :ready, prepare.first
  end

  def test_a_live_node_that_is_not_done_is_not_ready
    accepted_intent
    cli("node", "add", "1", "Extra", "--criterion", KEY)

    refute_equal :ready, prepare.first
  end

  def test_a_second_revise_is_a_refusal
    specified
    delivered_nodes
    put_verdict(1, "revise", MIDDLE)
    put_verdict(2, "revise", LATE)

    assert_kind_of Plastic::Refused, prepare.first
  end

  def test_a_missing_intent_fails_at_the_first_gate
    assert_includes prepare.first.message, "no intent 1 in this store"
  end

  def test_another_live_session_lock_is_refused
    accepted_intent
    store_graphs.work.take_lock("1", session_id: "s-2", mode: "auto")

    assert_kind_of Plastic::Refused, prepare.first
  end

  def test_a_done_intent_is_already_closed
    open_intent(status: "done")

    assert_equal :closed, prepare.first
  end

  def test_an_abandoned_intent_fails_the_call
    open_intent(status: "abandoned")

    assert_kind_of Plastic::Failed, prepare.first
  end
end

class PrepareEndingRecordsTest < PrepareEndingFixture
  def test_a_criterion_with_no_done_node_hands_over_naming_its_key
    accepted_intent
    write("#{open_intent_dir}/spec.md", keyed_spec({ KEY => CRITERION, "extra" => "Also" }))
    sync_up
    outcome, context = prepare

    assert_equal :agent_needed, outcome
    assert_includes context.requirements.join(" "), "extra"
  end

  def open_intent_dir = retrieval.intent("1").dir

  def test_without_the_merge_and_map_records_the_merge_check_comes_after_the_record_problems
    accepted_intent(records: nil)
    write("#{open_intent_dir}/outcome.md", "# Outcome\n\nDelivered.\n\n## Verification\n#{PULL_REQUEST}#{APPROVED}")
    sync_up

    assert_equal :unverified, prepare.first
  end

  def test_with_review_required_a_missing_pull_request_bullet_hands_over
    accepted_intent(records: MERGE_RECORDS)

    outcome, context = prepare

    assert_equal :agent_needed, outcome
    assert_includes context.requirements.join(" "), "Pull request:"
  end

  def test_with_review_required_a_pull_request_without_approval_is_a_refusal
    accepted_intent(records: MERGE_RECORDS + PULL_REQUEST)

    assert_kind_of Plastic::Refused, prepare.first
  end

  def test_with_review_off_no_pull_request_bullets_are_asked
    review_off
    accepted_intent(records: MERGE_RECORDS)

    assert_equal :ready, prepare.first
  end
end
