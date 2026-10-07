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

  def test_the_command_adds_the_worktree_on_its_branch
    found = worktree({ "plastic" => "/r/plastic" })

    assert_equal "git -C /r/plastic worktree add /r/plastic/.claude/worktrees/413--auto-id -b plastic/413--auto-id", found.command
  end

  def test_a_path_with_a_space_is_escaped
    found = worktree({ "plastic" => "/r/my repo" })

    assert_equal "git -C /r/my\\ repo worktree add /r/my\\ repo/.claude/worktrees/413--auto-id -b plastic/413--auto-id", found.command
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

  def test_present_says_whether_the_folder_exists
    found = worktree({ "plastic" => @home })
    before = found.present?
    FileUtils.mkdir_p(found.path)

    assert_equal [false, true], [before, found.present?]
  end
end
