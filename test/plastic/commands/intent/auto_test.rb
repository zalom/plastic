# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/intent/auto"

class IntentAutoTest < Plastic::TestCase
  include AutoHelper

  def test_a_clear_spec_with_a_go_ahead_goes_in_progress_and_offers_the_brief
    intent = clear_intent
    id = intent.intent_id

    result = call(id)

    assert_equal [0, "in_progress", [], "next: plastic intent brief #{id}"], [result.code, status_of(id), claim_rows, next_line(result)]
    assert_empty result.err
  end

  def test_an_intent_with_no_go_ahead_goes_in_progress_and_offers_the_spec
    intent = open_intent
    write_spec(intent, CLEAR_SPEC)

    result = call(intent.intent_id)

    assert_call result.with(out: next_line(result)), code: 0, err: "", out: "next: plastic intent spec 1"
    assert_equal "in_progress", status_of("1")
  end

  def test_an_open_decision_goes_in_progress_and_offers_the_spec
    intent = open_intent
    write_spec(intent, "# Spec\n\n## Done criteria\n- ships\n\n## Open Questions\n- which store wins\n")
    approve

    result = call(intent.intent_id)

    assert_equal [0, "in_progress", "next: plastic intent spec 1"], [result.code, status_of("1"), next_line(result)]
    assert_empty result.err
  end

  def test_no_done_criterion_goes_in_progress_and_offers_the_spec
    intent = open_intent
    write_spec(intent, "# Spec\n\n## Open Questions\n- none\n")
    approve

    result = call(intent.intent_id)

    assert_equal [0, "in_progress", "next: plastic intent spec 1"], [result.code, status_of("1"), next_line(result)]
    assert_empty result.err
  end

  def test_a_future_intent_goes_in_progress
    clear_intent(status: "future")

    result = call("1")

    assert_call result.with(out: next_line(result)), code: 0, err: "", out: "next: plastic intent brief 1"
    assert_equal "in_progress", status_of("1")
  end

  def test_a_parked_intent_resumes_in_progress
    clear_intent(status: "parked", reason: "waits on review")

    result = call("1")

    assert_call result.with(out: next_line(result)), code: 0, err: "", out: "next: plastic intent brief 1"
    assert_equal "in_progress", status_of("1")
  end

  def test_a_done_intent_exits_3_and_offers_plastic_next
    open_intent
    set_status("1", "done")

    result = call("1")

    assert_equal [3, "next: plastic next", "done"], [result.code, next_line(result), status_of("1")]
    assert_includes result.err, "intent 1 is done"
  end

  def archived_future_intent
    open_intent("Later", status: "future")
    as_session("intent", "archive", "1", env: {})
  end

  def test_an_archived_intent_exits_3_offers_unarchive_and_changes_nothing
    archived_future_intent

    result = call("1")

    assert_call result, code: 3, err: "plastic: refused, intent 1 is archived\nThis step belongs to the owner. Stop and ask; do not retry with a flag.\n",
      out: "next: plastic intent unarchive 1\nbecause: an archived intent cannot start; unarchive it first\n"
    assert_equal ["future", []], [status_of("1"), retrieval.unarchived_intents]
  end

  def test_a_call_with_no_session_fails_and_names_the_command
    intent = clear_intent

    result = call(intent.intent_id, env: { "PLASTIC_SESSION" => "" })

    assert_equal [1, [], "open"], [result.code, claim_rows, status_of("1")]
    assert_includes result.err, "plastic: intent auto names no session; set PLASTIC_SESSION"
  end

  def test_two_ids_exit_2_and_write_no_claim
    clear_intent
    write_spec(open_intent("Beta"), CLEAR_SPEC)

    result = call("1", "2")

    assert_equal [2, [], %w[open open]], [result.code, claim_rows, %w[1 2].map { |id| status_of(id) }]
    assert_includes result.err, "unexpected 2"
  end

  def test_no_id_exits_2
    result = call

    assert_equal [2, ""], [result.code, result.out]
    assert_includes result.err, "missing"
  end

  def test_a_missing_intent_fails
    result = call("9")

    assert_equal [1, []], [result.code, claim_rows]
    assert_includes result.err, "no intent 9 in this store"
  end

  def test_an_active_intent_stays_in_progress_and_takes_no_lock
    intent = active_intent

    result = call(intent.intent_id)

    assert_equal [0, "in_progress", []], [result.code, status_of(intent.intent_id), claim_rows]
  end

  def test_plastic_auto_is_an_unknown_command
    clear_intent

    result = plastic("auto", "1", env: { "PLASTIC_SESSION" => "s-1" }, table: Plastic::CLI::TABLE)

    assert_equal [2, "open"], [result.code, status_of("1")]
  end
end

class IntentAutoSessionTest < Plastic::TestCase
  include AutoHelper

  def ended_session_intent
    intent = clear_intent
    store_graphs.work.open_session("s-1", harness: "claude-code", directory: @home)
    store_graphs.work.end_session("s-1", reason: "clear")
    intent
  end

  def test_a_session_that_ended_exits_3_and_names_the_session
    result = call(ended_session_intent.intent_id)

    assert_equal 3, result.code
    assert_includes result.err, "session s-1 ended; start a new session or resume it"
  end

  def test_a_session_that_ended_offers_no_next_command
    refute_match(/^next: /, call(ended_session_intent.intent_id).out)
  end

  def test_a_session_that_ended_leaves_the_intent_open_with_no_claim
    intent = ended_session_intent
    call(intent.intent_id)

    assert_equal ["open", []], [status_of(intent.intent_id), claim_rows]
  end

  def test_a_session_reopened_after_its_end_starts_the_intent
    intent = ended_session_intent
    store_graphs.work.open_session("s-1", harness: "claude-code", directory: @home)

    result = call(intent.intent_id)

    assert_equal [0, "in_progress"], [result.code, status_of(intent.intent_id)]
  end
end

class IntentAutoWorktreeTest < Plastic::TestCase
  include AutoHelper

  def test_a_registered_repo_prints_the_path_and_branch_and_offers_the_brief
    repo = register_repo
    intent = clear_intent
    worktree = File.join(repo, ".claude", "worktrees", "1--alpha")
    FileUtils.mkdir_p(worktree)

    result = call(intent.intent_id)

    assert_equal [0, "next: plastic intent brief 1"], [result.code, next_line(result)]
    assert_includes result.out, "worktree: #{worktree}\n"
    assert_includes result.out, "branch: plastic/1--alpha\n"
  end

  def test_the_output_names_no_git_in_text_or_json
    register_repo
    intent = clear_intent
    text = call(intent.intent_id)
    json = call(intent.intent_id, "--json")

    assert_empty [text, json].flat_map { |result| result.out.scan(/\bgit\b/) }
  end

  def test_the_json_result_holds_the_path_and_branch_in_its_output
    repo = register_repo
    intent = clear_intent
    rows = JSON.parse(call(intent.intent_id, "--json").out).fetch("result").fetch("output")

    assert_includes rows.to_s, File.join(repo, ".claude", "worktrees", "1--alpha")
    assert_includes rows.to_s, "plastic/1--alpha"
  end

  def test_a_store_with_no_registered_repo_prints_no_worktree
    intent = clear_intent

    result = call(intent.intent_id)

    assert_equal 0, result.code
    refute_includes result.out, "worktree:"
  end

  def test_a_rerun_exits_0_and_prints_the_worktree_again
    register_repo
    intent = clear_intent
    call(intent.intent_id)

    result = call(intent.intent_id)

    assert_equal [0, "in_progress"], [result.code, status_of(intent.intent_id)]
    assert_includes result.out, "worktree: "
  end

  def test_a_missing_worktree_folder_prints_the_instruction_and_offers_intent_auto_again
    repo = register_repo
    intent = clear_intent

    result = call(intent.intent_id)

    worktree = File.join(repo, ".claude", "worktrees", "1--alpha")

    assert_call result, code: 0, err: "", out: ["worktree: #{worktree}\n", "branch: plastic/1--alpha\n", "next: plastic intent auto 1",
      "Create the worktree at #{worktree} on branch plastic/1--alpha, then run plastic intent auto 1 again. Use version control, such as Git, as the project's AGENTS.md or CLAUDE.md defines it, or as the project's history shows when neither does."]
  end

  def test_a_worktree_folder_that_exists_offers_the_brief_and_prints_no_instruction
    repo = register_repo
    intent = clear_intent
    FileUtils.mkdir_p(File.join(repo, ".claude", "worktrees", "1--alpha"))

    result = call(intent.intent_id)

    assert_equal [0, "next: plastic intent brief 1"], [result.code, next_line(result)]
    refute_includes result.out, "Create the worktree"
  end
end
