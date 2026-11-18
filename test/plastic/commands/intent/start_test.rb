# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/intent/start"

class IntentStartTest < Plastic::TestCase
  include AutoHelper

  def test_an_open_intent_goes_in_progress_and_offers_the_brief
    clear_intent

    result = start("1")

    assert_call result.with(out: next_line(result)), code: 0, err: "", out: "next: plastic intent brief 1"
    assert_equal "in_progress", status_of("1")
  end

  def test_a_future_intent_goes_in_progress
    clear_intent(status: "future")

    result = start("1")

    assert_call result.with(out: next_line(result)), code: 0, err: "", out: "next: plastic intent brief 1"
    assert_equal "in_progress", status_of("1")
  end

  def test_a_parked_intent_resumes_in_progress_and_keeps_its_reason
    clear_intent(status: "parked", reason: "waits on review")

    result = start("1")

    assert_call result.with(out: next_line(result)), code: 0, err: "", out: "next: plastic intent brief 1"
    assert_equal ["in_progress", "waits on review"], [status_of("1"), retrieval.intent("1").reason]
  end

  def test_an_in_progress_intent_stays_in_progress
    active_intent

    result = start("1")

    assert_call result.with(out: next_line(result)), code: 0, err: "", out: "next: plastic intent brief 1"
    assert_equal "in_progress", status_of("1")
  end

  def test_an_intent_with_no_go_ahead_goes_in_progress_and_offers_the_spec
    write_spec(open_intent(status: "future"), CLEAR_SPEC)

    result = start("1")

    assert_equal [0, "in_progress", "next: plastic intent spec 1"], [result.code, status_of("1"), next_line(result)]
    assert_empty result.err
  end

  def test_a_done_intent_exits_1_and_offers_plastic_next
    open_intent
    set_status("1", "done")

    result = start("1")

    assert_equal [1, "next: plastic next", "done"], [result.code, next_line(result), status_of("1")]
    assert_includes result.err, "intent 1 is done"
  end

  def test_an_abandoned_intent_exits_1_and_offers_plastic_next
    open_intent
    set_status("1", "abandoned")

    result = start("1")

    assert_equal [1, "next: plastic next", "abandoned"], [result.code, next_line(result), status_of("1")]
    assert_includes result.err, "intent 1 is abandoned"
  end

  def archived_future_intent
    open_intent("Later", status: "future")
    as_session("intent", "archive", "1", env: {})
  end

  def test_an_archived_intent_exits_1_offers_unarchive_and_changes_nothing
    archived_future_intent

    result = start("1")

    assert_call result, code: 1, err: "plastic: intent 1 is archived\n",
      out: "next: plastic intent unarchive 1\nbecause: an archived intent cannot start; unarchive it first\n"
    assert_equal ["future", []], [status_of("1"), retrieval.unarchived_intents]
  end

  def test_a_call_with_no_session_fails_and_names_the_command
    clear_intent(status: "future")

    result = start("1", env: { "PLASTIC_SESSION" => "" })

    assert_equal [1, "future"], [result.code, status_of("1")]
    assert_includes result.err, "plastic: intent start names no session; set PLASTIC_SESSION"
  end

  def test_a_missing_intent_fails
    result = start("9")

    assert_equal 1, result.code
    assert_includes result.err, "no intent 9 in this store"
  end

  def test_a_missing_worktree_folder_offers_intent_start_again
    repo = register_repo
    clear_intent

    result = start("1")

    worktree = File.join(repo, ".claude", "worktrees", "1--alpha")

    assert_call result, code: 0, err: "", out: ["worktree: #{worktree}\n", "branch: plastic/1--alpha\n", "next: plastic intent start 1",
      "Create the worktree at #{worktree} on branch plastic/1--alpha, then run plastic intent start 1 again. Use version control as the project's AGENTS.md or CLAUDE.md defines it, or as the project's history shows when neither does."]
  end
end
