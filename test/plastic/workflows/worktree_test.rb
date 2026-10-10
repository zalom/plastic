# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/worktree"

class WorkflowWorktreeTest < Plastic::TestCase
  Intent = Struct.new(:intent_id, :slug)
  Scope = Struct.new(:slug, :projects)

  def worktree(projects, slug: "plastic") = Plastic::Workflows::Worktree.of(Scope.new(slug, projects), Intent.new("413", "auto-id"))

  def test_a_registered_repo_gives_the_path_and_branch
    found = worktree({ "plastic" => "/r/plastic" })

    assert_equal ["/r/plastic", "/r/plastic/.claude/worktrees/413--auto-id", "plastic/413--auto-id"], [found.repo, found.path, found.branch]
  end

  def test_a_store_with_no_project_has_no_worktree
    assert_nil worktree({}, slug: "global")
  end

  def test_an_empty_project_path_has_no_worktree
    assert_nil worktree({ "plastic" => "" })
  end

  def test_no_scope_has_no_worktree
    assert_nil Plastic::Workflows::Worktree.of(nil, Intent.new("1", "a"))
  end
end
