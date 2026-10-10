# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/auto"

class AutoWorktreeTest < Plastic::TestCase
  include RoadmapHelper
  include AutoHelper

  def test_a_registered_repo_prints_the_path_and_branch_and_offers_the_brief
    repo = register_repo
    intent = clear_intent

    result = call(intent.intent_id)

    worktree = File.join(repo, ".claude", "worktrees", "1--alpha")

    assert_equal [0, "next: plastic intent brief 1 --project global"], [result.code, next_line(result)]
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
end
