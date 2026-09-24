# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/worktree"

# Hermetic tests for the `ensure_gitignored` safety helper (intent 73c3). It
# is plain file I/O (no git call ever runs from it), so no runner is faked
# here; `Worktree.finish` and the merge-vs-remove CLEANUP policy it used to
# carry were removed by intent 390 (Plastic runs no version control command).
class WorktreeCleanupTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("wtc-home")
    @repo = File.join(@home, "apps", "demo")
    FileUtils.mkdir_p(@repo)
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  # --- ensure_gitignored: appends once, idempotent ---------------------------

  def test_ensure_gitignored_appends_entry_when_absent
    assert Worktree.ensure_gitignored(@repo, ".claude/worktrees/")
    gitignore = File.join(@repo, ".gitignore")
    assert File.exist?(gitignore)
    assert_includes File.read(gitignore), ".claude/worktrees/"
  end

  def test_ensure_gitignored_idempotent_does_not_duplicate
    3.times { Worktree.ensure_gitignored(@repo, ".worktrees/") }
    count = File.read(File.join(@repo, ".gitignore")).each_line.count { |l| l.strip == ".worktrees/" }
    assert_equal 1, count, "entry must appear exactly once"
  end

  def test_ensure_gitignored_preserves_existing_content
    gitignore = File.join(@repo, ".gitignore")
    File.write(gitignore, "node_modules/\n*.log\n")
    Worktree.ensure_gitignored(@repo, ".claude/worktrees/")
    body = File.read(gitignore)
    assert_includes body, "node_modules/"
    assert_includes body, "*.log"
    assert_includes body, ".claude/worktrees/"
  end

  def test_ensure_gitignored_adds_trailing_newline_when_missing
    gitignore = File.join(@repo, ".gitignore")
    File.write(gitignore, "node_modules/") # no trailing newline
    Worktree.ensure_gitignored(@repo, ".worktrees/")
    lines = File.read(gitignore).each_line.map(&:strip)
    assert_includes lines, "node_modules/"
    assert_includes lines, ".worktrees/"
  end

  def test_ensure_gitignored_noop_for_blank_or_missing_repo
    refute Worktree.ensure_gitignored(nil, ".worktrees/")
    refute Worktree.ensure_gitignored(@repo, "")
    refute Worktree.ensure_gitignored(File.join(@home, "does-not-exist"), ".worktrees/")
  end
end
