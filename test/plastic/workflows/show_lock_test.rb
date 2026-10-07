# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/show_lock"

class WorkflowShowLockTest < Plastic::TestCase
  include DeliveryHelper

  def show(intent_id: "1")
    run_workflow(Plastic::Workflows::ShowLock, harness: scoped_harness(session: "s-1"), graphs: session_graphs, intent_id:)
  end

  def lines(context) = context.printed

  def expire_lock
    store_graphs.databases.fetch(:local).transaction do |batch|
      batch.add("UPDATE locks SET renewed_at = '2000-01-01T00:00:00Z'")
    end
  end

  def test_an_unknown_intent_fails
    outcome, = show(intent_id: "9")

    assert_equal "code_show_lock, gate: no intent 9 in this store", outcome.message
  end

  def test_no_lock_says_none
    open_intent

    outcome, context = show

    assert_equal [:none, ["lock: none"]], [outcome, lines(context)]
  end

  def test_a_live_lock_names_its_session
    open_intent
    store_graphs.work.take_lock("1", session_id: "s-2", mode: "auto")

    outcome, context = show

    assert_equal :live, outcome
    assert_match(/\Alock: session s-2, mode auto, taken \S+, renewed \S+, live\z/, lines(context).first)
  end

  def test_an_expired_lock_says_expired
    open_intent
    store_graphs.work.take_lock("1", session_id: "s-2", mode: "auto")
    expire_lock

    outcome, context = show

    assert_equal :expired, outcome
    assert_match(/, expired\z/, lines(context).first)
  end

  def test_a_registered_repo_prints_the_worktree
    File.write(File.join(@plastic_home, "projects.yml"), "projects:\n  global:\n    path: /r/repo\n")
    open_intent
    store_graphs.work.take_lock("1", session_id: "s-2", mode: "auto")

    _, context = show

    assert_equal "worktree: /r/repo/.claude/worktrees/1--alpha", lines(context).last
  end
end
