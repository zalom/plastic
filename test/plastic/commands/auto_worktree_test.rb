# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/auto"

class AutoWorktreeTest < Plastic::TestCase
  include RoadmapHelper
  include AutoHelper

  def test_a_registered_repo_prints_the_worktree_command_as_next
    repo = register_repo
    intent = clear_intent

    result = call(intent.intent_id)

    worktree = File.join(repo, ".claude", "worktrees", "1--alpha")

    assert_equal [0, "next: git -C #{repo} worktree add #{worktree} -b plastic/1--alpha"], [result.code, next_line(result)]
    assert_includes result.out, "worktree: #{worktree}\n"
    assert_includes result.out, "branch: plastic/1--alpha\n"
  end

  def test_an_existing_worktree_offers_the_brief
    repo = register_repo
    intent = clear_intent
    FileUtils.mkdir_p(File.join(repo, ".claude", "worktrees", "1--alpha"))

    result = call(intent.intent_id)

    assert_equal [0, "next: plastic intent brief 1 --project global"], [result.code, next_line(result)]
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
end
