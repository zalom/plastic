# frozen_string_literal: true

require "fileutils"
require_relative "../../test_helper"
require_relative "../../../lib/plastic/workflows/pull_request_template"

class PullRequestTemplateTest < Plastic::TestCase
  def repo = File.join(@home, "repo")

  def worktree = File.join(repo, ".claude", "worktrees", "1--alpha")

  def place(folder, relative)
    path = File.join(folder, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "## What\n")
  end

  def fact(tree = Plastic::Workflows::Worktree.new(repo:, path: worktree, branch: "plastic/1--alpha"))
    Plastic::Workflows::PullRequestTemplate.new(tree).fact
  end

  def said(place) = "The repository has a pull request template at #{place}; the description of the pull request follows it. "

  def test_a_template_in_the_worktree_of_the_intent_is_named
    place(worktree, ".github/pull_request_template.md")

    assert_equal said(".github/pull_request_template.md"), fact
  end

  def test_a_template_only_in_the_project_repository_is_named_when_the_worktree_is_missing
    place(repo, ".gitlab/merge_request_templates/default.md")

    assert_equal said(".gitlab/merge_request_templates/"), fact
  end

  def test_with_no_template_in_any_folder_the_fact_is_empty
    FileUtils.mkdir_p(worktree)

    assert_equal "", fact
  end

  def test_with_no_worktree_the_fact_is_empty
    assert_equal "", fact(nil)
  end

  def test_a_template_whose_name_differs_in_case_is_found_and_named_as_it_is_on_disk
    place(worktree, ".github/Pull_Request_Template.md")

    assert_equal said(".github/Pull_Request_Template.md"), fact
  end

  def test_a_folder_of_templates_whose_name_differs_in_case_is_found_and_named_as_it_is_on_disk
    place(worktree, ".github/pull_request_template/default.md")

    assert_equal said(".github/pull_request_template/"), fact
  end

  def test_a_template_folder_that_holds_no_markdown_file_is_not_a_template
    place(worktree, ".github/PULL_REQUEST_TEMPLATE/notes.txt")

    assert_equal "", fact
  end

  def test_an_empty_template_folder_is_not_a_template
    FileUtils.mkdir_p(File.join(worktree, ".gitlab", "merge_request_templates"))

    assert_equal "", fact
  end

  def test_a_template_folder_that_holds_a_markdown_file_in_capitals_is_a_template
    place(worktree, ".github/PULL_REQUEST_TEMPLATE/BUG.MD")

    assert_equal said(".github/PULL_REQUEST_TEMPLATE/"), fact
  end
end
