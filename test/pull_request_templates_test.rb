# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/pull_request_templates"

# PullRequestTemplates (intent 390): file-path detection only, no git call.
class PullRequestTemplatesTest < Minitest::Test
  def setup
    @repo = Dir.mktmpdir("prt-repo")
  end

  def teardown
    FileUtils.rm_rf(@repo)
  end

  def write(relative)
    path = File.join(@repo, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "template\n")
    path
  end

  def test_detects_github_root_template
    write(".github/pull_request_template.md")

    assert_equal [File.join(@repo, ".github/pull_request_template.md")], PullRequestTemplates.detect(@repo)
  end

  def test_detects_github_uppercase_template
    write(".github/PULL_REQUEST_TEMPLATE.md")

    assert_equal [File.join(@repo, ".github/PULL_REQUEST_TEMPLATE.md")], PullRequestTemplates.detect(@repo)
  end

  def test_detects_github_template_directory_entries
    write(".github/PULL_REQUEST_TEMPLATE/feature.md")

    assert_equal [File.join(@repo, ".github/PULL_REQUEST_TEMPLATE/feature.md")], PullRequestTemplates.detect(@repo)
  end

  def test_detects_docs_template
    write("docs/pull_request_template.md")

    assert_equal [File.join(@repo, "docs/pull_request_template.md")], PullRequestTemplates.detect(@repo)
  end

  def test_detects_gitlab_template_directory_entries
    write(".gitlab/merge_request_templates/feature.md")

    assert_equal [File.join(@repo, ".gitlab/merge_request_templates/feature.md")], PullRequestTemplates.detect(@repo)
  end

  def test_detects_none_when_no_template_exists
    assert_empty PullRequestTemplates.detect(@repo)
  end

  def test_detects_both_a_github_and_a_gitlab_template
    write(".github/PULL_REQUEST_TEMPLATE/feature.md")
    write(".gitlab/merge_request_templates/feature.md")
    found = PullRequestTemplates.detect(@repo)

    assert_equal 2, found.length
    assert_includes found, File.join(@repo, ".github/PULL_REQUEST_TEMPLATE/feature.md")
    assert_includes found, File.join(@repo, ".gitlab/merge_request_templates/feature.md")
  end

  def test_github_instruction_names_the_template_file_with_extension
    write(".github/PULL_REQUEST_TEMPLATE/feature.md")

    assert_equal ["gh pr create --template feature.md"], PullRequestTemplates.instructions(@repo)
  end

  def test_gitlab_instruction_names_the_template_without_extension
    write(".gitlab/merge_request_templates/feature.md")

    assert_equal ["glab mr create --template feature"], PullRequestTemplates.instructions(@repo)
  end

  def test_instructions_for_both_templates_together
    write(".github/PULL_REQUEST_TEMPLATE/feature.md")
    write(".gitlab/merge_request_templates/feature.md")
    lines = PullRequestTemplates.instructions(@repo)

    assert_includes lines, "gh pr create --template feature.md"
    assert_includes lines, "glab mr create --template feature"
  end

  def test_no_repository_yields_no_templates_or_instructions
    assert_empty PullRequestTemplates.detect(nil)
    assert_empty PullRequestTemplates.instructions("")
  end
end
