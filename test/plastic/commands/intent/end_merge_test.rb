# frozen_string_literal: true

require_relative "../../../test_helper"
require "plastic/commands/intent/end"

class IntentEndMergeTest < Plastic::TestCase
  include LifecycleHelper

  def finish = cli("intent", "end", "1")

  def lacking_merge_record
    accepted_intent(records: "- Architecture map: enola at abc123\n")
    review_off
  end

  def test_a_missing_merge_record_hands_over_the_merge_check_with_exit_1
    lacking_merge_record
    result = finish

    assert_equal [1, "in_progress"], [result.code, retrieval.intent("1").status]
    assert_includes result.out, "- Merged: "
  end

  def test_a_missing_merge_record_offers_the_end_again
    lacking_merge_record

    assert_match(/^next: plastic intent end 1/, finish.out)
  end

  def test_the_merge_handoff_offers_no_judge_or_evidence_option
    lacking_merge_record

    refute_match(/--judge|--evidence/, finish.out)
  end

  def test_the_merge_handoff_tells_the_agent_to_merge_its_own_pull_request
    lacking_merge_record
    out = finish.out

    assert_match(/merge (its|your) own pull request/i, out)
    assert_match(/only when the owner asked/i, out)
    assert_match(/plastic sync up/, out)
  end

  def test_a_negative_merge_record_is_named_by_the_handoff
    accepted_intent(records: "- Merged: no\n- Architecture map: enola at abc123\n")
    review_off

    assert_includes finish.out, "Merged: no"
  end

  def test_a_negative_approval_is_named_by_the_wait_for_the_person
    review_on
    accepted_intent(records: MERGE_RECORDS + PULL_REQUEST + "- Approved: no\n")
    result = finish

    assert_equal [3, "in_progress"], [result.code, retrieval.intent("1").status]
    assert_includes result.err + result.out, "Approved: no"
  end

  def test_the_printed_template_of_the_merge_line_closes_nothing
    accepted_intent(records: "- Merged: <branch> into <base> at <commit or pull request>\n- Architecture map: enola at abc123\n")
    review_off
    result = finish

    assert_equal [1, "in_progress"], [result.code, retrieval.intent("1").status]
    assert_includes result.out, "Merged: <branch> into <base> at <commit or pull request>"
  end

  def test_an_approval_that_is_only_requested_waits_for_the_person_and_shows_the_form
    review_on
    accepted_intent(records: MERGE_RECORDS + PULL_REQUEST + "- Approved: requested\n")
    result = finish

    assert_equal [3, "in_progress"], [result.code, retrieval.intent("1").status]
    assert_includes result.err + result.out, "Approved: <person> on <YYYY-MM-DD>"
  end

  def test_a_second_end_after_the_merge_record_resumes_and_closes
    lacking_merge_record
    first = finish
    write("#{retrieval.intent("1").dir}/outcome.md", "# Outcome\n\nDelivered and verified.\n\n## Verification\n#{MERGE_RECORDS}")
    sync_up
    second = finish

    assert_equal [1, 0, "done"], [first.code, second.code, retrieval.intent("1").status]
  end
end
