# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/commands/auto"

class AutoTest < Plastic::TestCase
  include RoadmapHelper
  include AutoHelper

  def test_a_clear_spec_goes_active_and_takes_the_lock
    intent = clear_intent

    id = intent.intent_id

    result = call(id)

    assert_equal [0, "in_progress", %w[s-1 auto]], [result.code, retrieval.intent(id).status, retrieval.lock(id).to_h.values_at(:session_id, :mode)]
    assert_includes result.out, "next: plastic intent brief #{id}"
    assert_empty result.err
  end

  def test_an_open_decision_refuses_and_the_status_stays_open
    intent = open_intent
    write_spec(intent, "# Spec\n\n## Done criteria\n- ships\n\n## Open Questions\n- which store wins\n")

    result = call(intent.intent_id)

    assert_equal [3, "open"], [result.code, retrieval.intent(intent.intent_id).status]
    assert_includes result.err, "intent 1 has an open decision; run plastic intent spec 1"
  end

  def test_no_done_criteria_exits_1_and_offers_the_spec
    intent = open_intent
    write_spec(intent, "# Spec\n\n## Open Questions\n- none\n")

    result = call(intent.intent_id)

    assert_equal 1, result.code
    assert_includes result.err, "intent 1 names no done criterion"
    assert_match(/^next: plastic intent spec 1/, result.out)
  end

  def test_another_sessions_live_lock_refuses_and_is_kept
    intent = clear_intent
    store_graphs.work.lock_intent(intent.intent_id, session_id: "s-2", mode: "auto")

    result = call(intent.intent_id)

    assert_equal [3, "s-2"], [result.code, retrieval.lock(intent.intent_id).session_id]
    assert_includes result.err, "intent 1 is locked by session s-2"
  end

  def test_a_done_intent_exits_1_and_offers_plastic_next
    open_intent
    store_graphs.databases.fetch(:work).transaction do |batch|
      batch.write(:intents, "UPDATE intents SET status = 'done' WHERE intent_id = :intent_id", intent_id: "1")
    end

    result = call("1")

    assert_equal 1, result.code
    assert_includes result.err, "intent 1 is done"
    assert_match(/^next: plastic next/, result.out)
  end

  def test_an_intent_with_a_criterion_and_no_go_ahead_still_exits_3
    intent = open_intent
    write_spec(intent, CLEAR_SPEC)

    result = call(intent.intent_id)

    assert_equal 3, result.code
    assert_includes result.err, "intent 1 has no go-ahead"
  end

  def test_a_call_with_no_session_fails
    intent = clear_intent

    result = call(intent.intent_id, env: { "PLASTIC_SESSION" => "" })

    assert_equal [1, []], [result.code, lock_rows]
    assert_includes result.err, "plastic: auto names no session; set PLASTIC_SESSION"
  end

  def test_two_ids_exit_2_and_write_no_lock
    clear_intent
    write_spec(open_intent("Beta"), CLEAR_SPEC)

    result = call("1", "2")

    assert_equal [2, [], %w[open open]], [result.code, lock_rows, %w[1 2].map { |id| retrieval.intent(id).status }]
    assert_includes result.err, "unexpected 2"
  end

  def test_no_id_exits_2
    result = call

    assert_equal [2, ""], [result.code, result.out]
    assert_includes result.err, "missing"
  end

  def test_a_missing_intent_fails
    result = call("9")

    assert_equal [1, []], [result.code, lock_rows]
    assert_includes result.err, "no intent 9 in this store"
  end

  def test_an_active_intent_without_a_lock_takes_one
    intent = active_intent

    result = call(intent.intent_id)

    lock = retrieval.lock(intent.intent_id)

    assert_equal [0, "s-1", "auto", true], [result.code, lock&.session_id, lock&.mode, lock && live_when_renewed?(lock)]
  end

  def test_an_expired_foreign_lock_is_taken_over
    intent = active_intent
    store_graphs.work.lock_intent(intent.intent_id, session_id: "s-2", mode: "auto")
    expire_lock

    result = call(intent.intent_id)

    assert_equal [0, "s-1", true], [result.code, *held_lock(intent.intent_id)]
  end
end

class AutoRoadmapTest < Plastic::TestCase
  include RoadmapHelper
  include AutoHelper

  def test_the_old_start_word_is_a_usage_error
    clear_intent

    result = call("start", "1")

    assert_equal [2, [], "open"], [result.code, lock_rows, retrieval.intent("1").status]
  end

  def test_auto_start_alone_reads_start_as_a_roadmap
    result = call("start")

    assert_equal [1, []], [result.code, lock_rows]
    assert_includes result.err, "no roadmap start"
  end

  def test_an_intent_shaped_slug_reads_as_an_intent
    store_graphs.work.write_batch("2026", 1, fields: roadmap_fields("T", goal: "G", done: "d"))

    result = call("2026")

    assert_equal 1, result.code
    assert_includes result.err, "no intent 2026 in this store"
  end

  def test_an_unknown_roadmap_fails
    result = call("r9")

    assert_equal [1, []], [result.code, lock_rows]
    assert_includes result.err, "no roadmap r9"
  end

  def test_a_roadmap_item_without_a_go_ahead_is_refused_with_no_lock
    roadmap
    item("a")
    intent_id, = store_graphs.work.open_roadmap_item("r1", "a")

    result = call("r1")

    assert_equal [3, []], [result.code, lock_rows]
    assert_includes result.err, "plastic intent approve #{intent_id}"
  end

  def test_a_roadmap_arms_its_in_flight_item
    roadmap
    item("a")
    intent_id, = store_graphs.work.open_roadmap_item("r1", "a")
    plastic("intent", "approve", intent_id, table: Plastic::CLI::TABLE)

    result = call("r1")

    assert_equal [0, "s-1", "in_progress"], [result.code, retrieval.lock(intent_id)&.session_id, retrieval.intent(intent_id).status]
  end

  def test_a_roadmap_with_a_ready_item_offers_roadmap_open
    roadmap
    item("a")

    result = call("r1")

    assert_equal [0, [], "next: plastic roadmap open r1 a"], [result.code, lock_rows, next_line(result)]
  end

  def test_a_resumed_roadmap_call_never_arms_a_stale_intent
    roadmap
    item("a")
    item("b")
    store_graphs.work.open_roadmap_item("r1", "a")
    failed = call("r1", env: { "PLASTIC_SESSION" => "" })
    store_graphs.work.drop_item("r1", "a")

    result = call("r1")

    assert_equal [1, 0, [], "next: plastic roadmap open r1 b"], [failed.code, result.code, lock_rows, next_line(result)]
  end

  def armed_item
    roadmap
    item("a")
    intent_id, = store_graphs.work.open_roadmap_item("r1", "a")
    plastic("intent", "approve", intent_id, table: Plastic::CLI::TABLE)
    intent_id
  end

  def test_a_roadmap_whose_picked_intent_has_a_savepoint_changed_by_hand_is_refused_and_kept
    intent_id = armed_item
    path = "#{retrieval.intent(intent_id).dir}/savepoint.md"
    write(path, "by hand\n")

    result = call("r1")

    assert_equal [1, [], "by hand\n", true, "next: plastic sync up"], [result.code, lock_rows, File.read(store_path(path)), result.err.include?("#{path} changed since its last print on this home"), next_line(result)], result.err
  end

  def test_a_roadmap_with_a_ready_item_is_not_refused_for_a_file_of_another_intent
    roadmap
    item("a")
    other = open_intent("Other")
    write("#{other.dir}/savepoint.md", "by hand\n")

    result = call("r1")

    assert_equal [0, "next: plastic roadmap open r1 a"], [result.code, next_line(result)], result.err
  end

  def test_a_delivered_roadmap_offers_roadmap_show_and_is_not_refused
    roadmap
    item("a")
    store_graphs.work.drop_item("r1", "a")

    result = call("r1")

    assert_equal [0, "next: plastic roadmap show r1"], [result.code, next_line(result)], result.err
  end
end

class AutoSessionTest < Plastic::TestCase
  include RoadmapHelper
  include AutoHelper

  def ended_session_intent
    intent = clear_intent
    store_graphs.work.open_session("s-1", harness: "claude-code", directory: @home)
    store_graphs.work.end_session("s-1", reason: "clear")
    intent
  end

  def test_a_session_that_ended_exits_1_and_names_the_session
    result = call(ended_session_intent.intent_id)

    assert_equal 1, result.code
    assert_includes result.err, "session s-1 ended; start a new session or resume it"
  end

  def test_a_session_that_ended_offers_no_next_command
    refute_match(/^next: /, call(ended_session_intent.intent_id).out)
  end

  def test_a_session_that_ended_leaves_the_intent_open_with_no_lock
    intent = ended_session_intent
    call(intent.intent_id)

    assert_equal ["open", []], [retrieval.intent(intent.intent_id).status, lock_rows]
  end

  def test_a_session_reopened_after_its_end_locks_the_intent
    intent = ended_session_intent
    store_graphs.work.open_session("s-1", harness: "claude-code", directory: @home)

    result = call(intent.intent_id)

    assert_equal [0, "s-1", true], [result.code, *held_lock(intent.intent_id)]
  end
end

class AutoWorktreeTest < Plastic::TestCase
  include RoadmapHelper
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

    assert_equal [0, "s-1"], [result.code, retrieval.lock(intent.intent_id).session_id]
    assert_includes result.out, "worktree: "
  end

  def test_a_missing_worktree_folder_prints_the_instruction_and_offers_auto_again
    repo = register_repo
    intent = clear_intent

    result = call(intent.intent_id)

    worktree = File.join(repo, ".claude", "worktrees", "1--alpha")

    assert_equal [0, "next: plastic auto 1"], [result.code, next_line(result)]
    assert_includes result.out, "Create the worktree at #{worktree} on branch plastic/1--alpha, then run plastic auto 1 again. Use version control as the project's AGENTS.md or CLAUDE.md defines it, or as the project's history shows when neither does."
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
