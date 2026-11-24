# frozen_string_literal: true

require_relative "../../../test_helper"

class IntentAbandonCaseTest < Plastic::TestCase
  OUTCOME = "# Outcome\nDropped.\n\n## Verification\n- Reverted: nothing delivered\n"

  def abandoned
    ran("intent new Alpha")
    write("store/1--alpha/outcome.md", OUTCOME)
    sync_up
  end

  def test_abandoning_prints_the_status_and_the_stop_step_for_the_processes
    abandoned

    assert_case line("intent abandon 1"), code: 0, out: ["intent: 1 abandoned",
      "1. Stop the processes and the agents that intent 1 started: servers, watchers, background jobs and subagents. " \
      "Plastic runs none of them and stops none of them."]
  end

  def test_abandoning_an_abandoned_intent_exits_3_and_says_it_cannot
    abandoned
    ran("intent abandon 1")

    assert_case line("intent abandon 1"), code: 3, out: "", err: ["intent 1 is abandoned; it can no longer be abandoned"]
  end

  def test_abandoning_a_missing_intent_exits_1_and_names_it
    assert_case line("intent abandon 9"), code: 1, out: "", err: ["no intent 9 in this store"]
  end
end

class IntentAbandonTest < Plastic::TestCase
  include LifecycleHelper

  REVERTED = "\n## Verification\n- Reverted: nothing delivered\n"

  def droppable(reverted: true, **fields)
    intent = open_intent("Alpha", **fields)
    write("#{intent.dir}/outcome.md", "# Outcome\n\nDropped: the need went away.\n#{REVERTED if reverted}")
    cli("store", "sync", "up")
    intent
  end

  def abandon(*extra) = cli("intent", "abandon", "1", *extra)

  def supersede(from, to)
    store_graphs.databases.fetch(:store).transaction do |batch|
      batch.put(:links, { from_ref: from, to_ref: to, kind: "supersedes", at: LifecycleHelper::EARLY })
    end
  end

  def test_an_option_is_a_usage_error
    droppable

    result = abandon("--judge", "agent")

    assert_equal [2, "open"], [result.code, retrieval.intent("1").status]
    assert_includes result.err, "invalid option: --judge"
  end

  def test_a_started_intent_without_the_reverted_bullet_hands_over_the_revert_steps
    droppable(reverted: false, status: "in_progress")
    result = abandon

    assert_equal [0, "in_progress"], [result.code, retrieval.intent("1").status]
    assert_includes result.out, "Reverted:"
  end

  def test_an_open_intent_with_a_node_without_the_reverted_bullet_hands_over_the_revert_steps
    droppable(reverted: false)
    store_graphs.work.add_node(intent_id: "1", title: "Build")
    result = abandon

    assert_equal [0, "open"], [result.code, retrieval.intent("1").status]
    assert_includes result.out, "Reverted:"
  end

  %w[future open].each do |status|
    define_method(:"test_an_unstarted_#{status}_intent_with_no_node_closes_with_no_reverted_bullet") do
      droppable(reverted: false, status:)
      result = abandon

      assert_equal [0, "", "abandoned"], [result.code, result.err, retrieval.intent("1").status]
      assert_includes result.out, "intent: 1 abandoned"
    end
  end

  def test_the_revert_step_tells_the_agent_to_use_version_control_as_the_project_defines_it
    droppable(reverted: false, status: "in_progress")
    result = abandon

    refute_includes result.out, "your own"
    assert_call result, code: 0, out: [
      "Use version control, such as Git, as the project's AGENTS.md or CLAUDE.md defines it, or as the project's history shows when neither does: undo what intent 1 changed, close or delete its branch and worktree, and revert any commit that reached the base.",
      "Plastic runs no version control command; it records what you write.",
      "Write in store/1--alpha/outcome.md why the intent is dropped, and add the line '- Reverted: <what was undone, or nothing delivered>' under ## Verification. Run plastic store sync up and then plastic intent abandon 1 again."
    ]
  end

  def test_with_the_reverted_bullet_it_closes_cancelled_with_no_completion
    droppable
    result = abandon

    assert_equal 0, result.code
    assert_equal ["abandoned", "cancelled", nil], [retrieval.intent("1").status, retrieval.intent("1").disposition, structure.completions("1").first]
  end

  def test_a_supersedes_link_from_another_intent_gives_superseded
    droppable
    open_intent("Beta")
    supersede("2", "1")
    abandon

    assert_equal "superseded", retrieval.intent("1").disposition
  end

  def test_a_supersedes_link_from_this_intent_to_another_gives_cancelled
    droppable
    open_intent("Beta")
    supersede("1", "2")
    abandon

    assert_equal "cancelled", retrieval.intent("1").disposition
  end

  def test_a_supersedes_link_between_rulings_of_this_intent_gives_cancelled
    droppable
    supersede("1/D2", "1")
    abandon

    assert_equal "cancelled", retrieval.intent("1").disposition
  end

  %w[done abandoned].each do |status|
    define_method(:"test_a_#{status}_intent_fails") do
      open_intent(status:)

      assert_equal 3, abandon.code
    end
  end

  def test_a_live_claim_of_another_session_refuses_with_exit_3
    droppable
    store_graphs.work.add_node(intent_id: "1", title: "Build")
    store_graphs.work.claim_node(intent_id: "1", id: "n1", by: "someone-else")

    assert_equal [3, "open"], [abandon.code, retrieval.intent("1").status]
  end
end
