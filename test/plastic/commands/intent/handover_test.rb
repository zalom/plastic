# frozen_string_literal: true

require_relative "../../../test_helper"

# An intent whose two review rounds are used, with a second intent to take over its last gap.
module HandoverFixture
  REASON = "Intent 2 carries the last gap"
  LINE = "Handed over to 2 by the owner: #{REASON}"
  DROPPED = "# Outcome\n\nDropped.\n\n## Verification\n- Abandoned: dropped because the need went away\n- Reverted: nothing delivered\n"

  def handed_over_lines = work_rows("work_log").select { |row| row.fetch("kind") == "handed_over" }.map { |row| row.fetch("text") }

  def handover(*args) = cli("intent", "handover", "1", *args)

  def used_up
    cli("intent", "verdict", "1", "revise", "one")
    cli("intent", "verdict", "1", "revise", "two")
  end

  def follow_up = open_intent("Follow up")

  def handed_over
    used_up
    follow_up
    handover("2", REASON, "--owner")
  end
end

class IntentHandoverTest < Plastic::TestCase
  include LifecycleHelper
  include HandoverFixture

  def setup
    super
    specified
    delivered_nodes
  end

  def test_the_owner_handover_writes_one_line_naming_the_follow_up_and_offers_the_end
    used_up
    follow_up
    result = handover("2", REASON, "--owner")

    assert_call result, code: 0, out: ["next: plastic intent end 1"], err: ""
    assert_equal [LINE], handed_over_lines
  end

  def test_the_handover_prints_the_work_log_of_the_intent
    handed_over

    assert_includes File.read(store_path("store/1--alpha/work.log")), LINE
  end

  def test_a_handover_of_a_parked_intent_offers_its_start
    used_up
    follow_up
    cli("intent", "park", "1", "Waits for the follow-up")
    result = handover("2", REASON, "--owner")

    assert_call result, code: 0, out: ["next: plastic intent start 1"], err: ""
    assert_equal [LINE], handed_over_lines
  end

  def test_a_handover_without_owner_exits_2_with_no_line
    used_up
    follow_up
    result = handover("2", REASON)

    assert_call result, code: 2, out: "", err: ["--owner"]
    assert_equal [], handed_over_lines
  end

  def test_a_handover_without_a_reason_exits_2_with_no_line
    used_up
    follow_up

    assert_equal [2, []], [handover("2", "--owner").code, handed_over_lines]
  end

  def test_a_handover_of_a_missing_intent_exits_1_with_no_line
    follow_up
    result = cli("intent", "handover", "9", "2", REASON, "--owner")

    assert_call result, code: 1, out: "", err: ["no intent 9 in this store"]
    assert_equal [], handed_over_lines
  end

  def test_a_handover_to_a_missing_follow_up_exits_1_with_no_line
    used_up
    result = handover("9", REASON, "--owner")

    assert_call result, code: 1, out: "", err: ["no intent 9 in this store to take over the last gap of intent 1"]
    assert_equal [], handed_over_lines
  end

  def test_a_handover_to_the_intent_itself_exits_3_with_no_line
    used_up
    result = handover("1", REASON, "--owner")

    assert_call result, code: 3, out: "", err: ["intent 1 cannot take over its own last gap; name another intent"]
    assert_equal [], handed_over_lines
  end

  def test_a_handover_to_an_abandoned_follow_up_exits_3_with_no_line
    used_up
    follow_up
    write("store/2--follow-up/outcome.md", DROPPED)
    cli("store", "sync", "up")
    cli("intent", "abandon", "2")
    result = handover("2", REASON, "--owner")

    assert_call result, code: 3, out: "", err: ["intent 2 is abandoned, so it cannot take over the last gap of intent 1"]
    assert_equal [], handed_over_lines
  end

  def test_a_handover_with_a_round_left_exits_3_with_no_line
    cli("intent", "verdict", "1", "revise", "one")
    follow_up
    result = handover("2", REASON, "--owner")

    assert_call result, code: 3, out: "", err: ["intent 1 still has a review round left or holds an accepted review; a handover needs the rounds used"]
    assert_equal [], handed_over_lines
  end

  def test_a_second_handover_exits_3_and_keeps_one_line
    handed_over
    result = handover("2", REASON, "--owner")

    assert_call result, code: 3, out: "", err: ["intent 1 is already handed over"]
    assert_equal [LINE], handed_over_lines
  end
end

class IntentHandoverClosedTest < Plastic::TestCase
  include LifecycleHelper
  include HandoverFixture

  def test_a_handover_of_a_done_intent_exits_3_with_no_line
    accepted_intent
    review_off
    cli("intent", "end", "1")
    follow_up
    result = handover("2", REASON, "--owner")

    assert_call result, code: 3, out: "", err: ["intent 1 is done"]
    assert_equal [], handed_over_lines
  end
end

class IntentEndAfterHandoverTest < Plastic::TestCase
  include LifecycleHelper
  include HandoverFixture

  def setup
    super
    specified
    delivered_nodes
    review_off
  end

  def test_after_a_handover_the_end_closes_the_intent_as_delivered_with_no_revert
    handed_over
    result = cli("intent", "end", "1")
    row = store_graphs.databases.fetch(:store).rows("SELECT status, disposition FROM intents WHERE intent_id = '1'").first

    assert_call result, code: 0, out: ["intent: 1 done"], err: ""
    assert_equal [{ "status" => "done", "disposition" => "delivered" }, 1], [row, work_rows("completions").size]
  end

  def test_after_a_handover_the_end_does_not_wait_for_the_follow_up
    handed_over
    cli("intent", "end", "1")

    assert_equal %w[done open], [retrieval.intent("1").status, retrieval.intent("2").status]
  end

  def test_after_a_handover_the_end_still_stops_on_a_missing_delivery
    write("store/1--alpha/outcome.md", "# Outcome\n\nDelivered.\n\n## Verification\n")
    cli("store", "sync", "up")
    handed_over
    result = cli("intent", "end", "1")

    assert_equal [0, "in_progress", 0], [result.code, retrieval.intent("1").status, work_rows("completions").size]
  end

  def test_without_a_handover_the_end_of_a_used_round_is_refused
    used_up
    result = cli("intent", "end", "1")

    assert_call result, code: 3, out: "", err: ["plastic intent handover 1 FOLLOW_UP REASON --owner"]
    assert_equal "in_progress", retrieval.intent("1").status
  end

  def test_after_a_later_grant_the_end_needs_an_accepted_verdict_again
    handed_over
    cli("intent", "grant", "1", "One more look", "--owner")
    result = cli("intent", "end", "1")

    assert_equal [0, "in_progress", 0], [result.code, retrieval.intent("1").status, work_rows("completions").size]
  end

  def test_after_a_later_grant_and_a_third_revise_the_old_handover_no_longer_counts
    handed_over
    cli("intent", "grant", "1", "One more look", "--owner")
    cli("intent", "verdict", "1", "revise", "three")
    result = cli("intent", "end", "1")

    assert_equal [3, "in_progress"], [result.code, retrieval.intent("1").status]
  end
end
