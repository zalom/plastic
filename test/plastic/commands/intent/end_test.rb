# frozen_string_literal: true

require_relative "../../../test_helper"
require "plastic/commands/intent/end"

class IntentEndAcceptedCaseTest < Plastic::TestCase
  include LifecycleHelper

  def test_an_accepted_close_leaves_the_intent_done_with_one_completion_and_no_next_line
    accepted_intent
    review_off
    result = cli("intent", "end", "1", session: "delivery")

    assert_equal [0, "done", 1], [result.code, retrieval.intent("1").status, work_rows("completions").size]
    refute_match(/^next:/, result.out)
  end

  def test_ending_an_intent_with_a_done_node_adds_a_done_line_with_no_node
    accepted_intent
    review_off
    cli("intent", "end", "1", session: "delivery")
    done = retrieval.structure.work_log("1").select { |line| line.kind == "done" }

    assert_equal ["n1", ""], done.map(&:node)
    assert_equal "Done", done.last.text
  end
end

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

      assert_equal [2, "in_progress"], [result.code, retrieval.intent("1").status]
    end
  end

  def test_abandoned_is_a_usage_error
    accepted_intent

    assert_equal [2, "in_progress"], [cli("intent", "end", "1", "--abandoned").code, retrieval.intent("1").status]
  end

  def test_with_every_row_good_and_review_off_the_intent_closes_delivered
    accepted_intent(records: MERGE_RECORDS)
    review_off

    result = finish

    assert_equal 0, result.code
    assert_equal ["done", "delivered"], retrieval.intent("1").to_h.values_at(:status, :disposition)
  end

  def test_the_completion_row_holds_the_verdict_judge_and_the_criteria
    closed_intent
    row = structure.completions("1").first

    assert_equal "verdict", row.judge
    assert_equal({ KEY => CRITERION }, JSON.parse(row.criteria))
  end

  def test_the_completion_evidence_maps_each_key_to_node_ids_and_findings
    closed_intent
    evidence = JSON.parse(structure.completions("1").first.evidence)

    assert_includes evidence.fetch(KEY).to_s, "n1"
    assert_includes evidence.fetch(KEY).to_s, "Acceptance passes for works"
  end

  def test_the_close_prints_the_index_showing_the_intent_done
    accepted_intent
    review_off

    finish

    assert_equal "done", listed("1").fetch("status")
  end

  def test_the_output_of_the_close_names_the_wind_down_step
    accepted_intent
    review_off

    assert_match(/stop/i, finish.out)
  end

  def test_a_second_end_exits_0_says_the_intent_is_already_done_and_keeps_one_completion_row
    closed_intent

    result = finish

    assert_equal [0, 1, ""], [result.code, work_rows("completions").size, result.err]
    assert_match(/already done/, result.out)
    assert_match(/^next: plastic next/, result.out)
  end

  def test_a_live_claim_of_another_session_refuses_the_close
    accepted_intent
    review_off
    node = store_graphs.work.add_node(intent_id: "1", title: "Build")
    store_graphs.work.claim_node(intent_id: "1", id: node.id, by: "someone-else")

    result = finish

    assert_equal [3, "in_progress"], [result.code, retrieval.intent("1").status]
  end

  def test_with_no_verdict_the_handoff_names_the_judge_command
    specified
    delivered_nodes
    review_off

    result = finish

    assert_equal [1, "in_progress", 0], [result.code, retrieval.intent("1").status, work_rows("completions").size]
    assert_includes result.out, "plastic intent judge 1"
    assert_match(/^next: plastic intent end 1/, result.out)
  end

  def test_the_handoff_because_names_the_missing_outcome_and_not_the_judge
    accepted_intent(records: nil)
    review_off

    because = finish.out.lines(chomp: true).grep(/\Abecause:/).first

    assert_match(/outcome\.md/, because)
    refute_match(/judged/, because)
  end

  def test_the_chain_has_no_problems
    assert_empty Plastic::Commands::Intent::End.chain_problems
  end
end

class IntentEndPullRequestTest < Plastic::TestCase
  include LifecycleHelper

  def finish = cli("intent", "end", "1")

  def test_required_without_a_pull_request_bullet_hands_over_the_record_step
    review_on
    accepted_intent(records: MERGE_RECORDS)

    result = finish

    assert_equal [1, "in_progress"], [result.code, retrieval.intent("1").status]
    assert_includes result.out, "Pull request:"
  end

  def test_required_with_a_pull_request_and_no_approval_waits_for_the_person
    review_on
    accepted_intent(records: MERGE_RECORDS + PULL_REQUEST)

    result = finish

    assert_equal [3, "in_progress"], [result.code, retrieval.intent("1").status]
    assert_match(/approval/i, result.err + result.out)
  end

  def test_required_with_no_verdict_and_no_pull_request_lists_both
    review_on
    specified(records: MERGE_RECORDS)
    delivered_nodes

    result = finish

    assert_equal [1, "in_progress"], [result.code, retrieval.intent("1").status]
    assert_includes result.out, "plastic intent judge 1"
    assert_includes result.out, "Pull request:"
  end

  def test_required_with_the_approval_closes
    review_on
    accepted_intent

    assert_equal [0, "done"], [finish.code, retrieval.intent("1").status]
  end

  def test_with_no_config_the_intent_closes_with_no_pull_request_bullets
    accepted_intent(records: MERGE_RECORDS)

    assert_equal [0, "done"], [finish.code, retrieval.intent("1").status]
  end

  def test_a_merge_record_with_no_architecture_map_line_closes
    accepted_intent(records: "- Merged: plastic/1 into alpha at abc123\n")

    assert_equal [0, "done"], [finish.code, retrieval.intent("1").status]
  end

  def test_an_old_architecture_map_line_beside_the_merge_record_is_ignored
    accepted_intent(records: "- Merged: plastic/1 into alpha at abc123\n- Architecture map: enola at abc123\n")

    assert_equal [0, "done"], [finish.code, retrieval.intent("1").status]
  end

  def test_off_closes_with_no_pull_request_bullets
    accepted_intent(records: MERGE_RECORDS)
    review_off

    assert_equal [0, "done"], [finish.code, retrieval.intent("1").status]
  end
end

class IntentEndMergeTest < Plastic::TestCase
  include LifecycleHelper

  def finish = cli("intent", "end", "1")

  def lacking_merge_record
    accepted_intent(records: "- Tests pass\n")
    review_off
  end

  def test_a_missing_merge_record_hands_over_the_merge_check_with_exit_1
    lacking_merge_record
    result = finish

    assert_equal [1, "in_progress", 0], [result.code, retrieval.intent("1").status, work_rows("completions").size]
    assert_includes result.out, "- Merged: "
    assert_match(/^next: plastic intent end 1/, result.out)
  end

  def test_a_missing_merge_record_offers_the_end_again
    lacking_merge_record

    assert_match(/^next: plastic intent end 1/, finish.out)
  end

  def test_the_merge_handoff_offers_no_judge_or_evidence_option
    lacking_merge_record

    refute_match(/--judge|--evidence/, finish.out)
  end

  def test_the_merge_handoff_tells_the_agent_to_merge_the_pull_request_with_the_projects_version_control
    lacking_merge_record
    out = finish.out

    assert_match(/AGENTS\.md or CLAUDE\.md/, out)
    assert_match(/merge the pull request of intent 1 into the intent's base/, out)
  end

  def test_the_merge_handoff_leaves_the_pull_request_open_only_when_the_owner_asked_and_names_sync_up
    lacking_merge_record
    out = finish.out

    assert_match(/only when the owner asked/i, out)
    assert_match(/plastic store sync up/, out)
  end

  def test_a_negative_merge_record_is_named_by_the_handoff
    accepted_intent(records: "- Merged: no\n")
    review_off
    result = finish

    assert_equal [1, "in_progress"], [result.code, retrieval.intent("1").status]
    assert_includes result.out, "Merged: no"
    assert_match(/^next: plastic intent end 1/, result.out)
  end

  def test_a_negative_approval_is_named_by_the_wait_for_the_person
    review_on
    accepted_intent(records: MERGE_RECORDS + PULL_REQUEST + "- Approved: no\n")
    result = finish

    assert_equal [3, "in_progress"], [result.code, retrieval.intent("1").status]
    assert_includes result.err + result.out, "Approved: no"
  end

  def test_the_printed_template_of_the_merge_line_closes_nothing
    accepted_intent(records: "- Merged: <branch> into <base> at <commit or pull request>\n")
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

  def test_a_direct_commit_with_the_architecture_map_closes_the_intent
    accepted_intent(records: "- Committed: main at 4f2a9c1\n")
    review_off

    assert_equal [0, "done"], [finish.code, retrieval.intent("1").status]
  end

  def test_delivered_files_in_the_intent_folder_close_the_intent_with_no_architecture_map
    accepted_intent(records: "- Delivered: resources/output/files/resume.pdf because the resume lives outside version control\n")
    write("#{retrieval.intent("1").dir}/resources/output/files/resume.pdf", "%PDF")
    review_off

    assert_equal [0, "done"], [finish.code, retrieval.intent("1").status]
  end

  def test_delivered_files_missing_from_the_intent_folder_hand_over_the_delivery_check_naming_the_path
    accepted_intent(records: "- Delivered: resources/output/files/resume.pdf because the resume lives outside version control\n")
    review_off
    result = finish

    assert_equal [1, "in_progress"], [result.code, retrieval.intent("1").status]
    assert_includes result.out, "resources/output/files/resume.pdf"
  end

  def test_the_delivery_handoff_names_the_three_lines_and_the_output_folders
    lacking_merge_record
    out = finish.out

    ["- Merged: ", "- Committed: ", "- Delivered: ", "resources/output/reports", "resources/output/files"].each { |part| assert_includes out, part }
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
