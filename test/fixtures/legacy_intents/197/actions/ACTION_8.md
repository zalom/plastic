# ACTION_8 - new lib: scripts/lib/maintenance_git.rb (clean-tree, branch, scoped commit, merge-back)

Covers the git-isolation half of the maintenance mechanism (spec.md dispatch brief task 4:
"branch-and-merge model... never `git add -A`"). This module is pure infrastructure with no
caller yet; ACTION_9 (`scripts/maintenance-run`) wires it to the three code tools, and
ACTION_7's curator doctrine describes the same recipe by hand for agent-driven edits.

**Design decision: require a clean working tree before starting, rather than diff dirty-state
before/after.** `~/.plastic` is a single, live, shared git repository (confirmed:
`git -C ~/.plastic rev-parse --show-toplevel` from ANY project's store resolves to the same
`~/.plastic` root; discovery + a live check both confirm this). It already has unrelated
uncommitted changes today (`.cache/update-check.json`, `manifest.json`, an audit dry-run file).
A before/after dirty-path diff would silently miss a case where the block re-touches an
already-dirty path. Refusing to start until the tree is clean is simpler, cannot silently
mis-attribute a change, and matches D12/D13's "avoid clobbering by construction."

File: new `scripts/lib/maintenance_git.rb` (inside the worktree).

## 8a. The module

```ruby
# encoding: UTF-8
# frozen_string_literal: true

require "open3"

# MaintenanceGit - git isolation for a maintenance action (intent 197, D12/D13): a fresh
# branch off the CURRENT tip of `base`, the caller's block runs, only the paths the block
# ACTUALLY changed are staged (never `git add -A`), committed, and the branch is merged back
# to `base` as part of the SAME closed operation before this method returns. Nothing strands
# on an unmerged branch; nothing outside the block's own change is ever touched.
#
# Requires a CLEAN working tree before starting (see module doc above for why); refuses
# loudly rather than attempt to distinguish pre-existing dirt from the block's own changes.
# On any error inside the block, the working tree is hard-reset and returned to `base` before
# re-raising, which is SAFE only because the precondition already proved nothing else was
# dirty when the branch was created.
module MaintenanceGit
  module_function

  class NotAGitRepo < StandardError; end
  class DirtyWorkingTree < StandardError; end

  def git_toplevel(dir)
    out, _err, status = Open3.capture3("git", "-C", dir, "rev-parse", "--show-toplevel")
    return nil unless status.success?

    top = out.strip
    top.empty? ? nil : top
  end

  # Bare paths (status prefix stripped), relative to `root`. Empty array on a clean tree.
  def porcelain_paths(root)
    out, _err, status = Open3.capture3("git", "-C", root, "status", "--porcelain")
    return [] unless status.success?

    out.lines.map { |l| l[3..].to_s.strip }.reject(&:empty?)
  end

  # Runs `block` inside a fresh branch off `base`'s current tip. Returns
  # { changed: [...], committed: bool, merged: bool, branch: name }.
  def run_scoped(repo_dir:, branch_name:, commit_message:, base: "main")
    root = git_toplevel(repo_dir)
    raise NotAGitRepo, "#{repo_dir} is not inside a git repository" unless root

    dirty = porcelain_paths(root)
    unless dirty.empty?
      raise DirtyWorkingTree,
            "#{root} has #{dirty.size} uncommitted path(s) before maintenance started; " \
            "commit or stash them first (never swept via git add -A): #{dirty.join(", ")}"
    end

    checkout!(root, base)
    run_git!(root, "checkout", "--quiet", "-b", branch_name)

    begin
      yield
    rescue StandardError
      run_git!(root, "reset", "--hard", "--quiet")
      run_git!(root, "clean", "-fd", "--quiet")
      checkout!(root, base)
      delete_branch(root, branch_name)
      raise
    end

    changed = porcelain_paths(root)
    if changed.empty?
      checkout!(root, base)
      delete_branch(root, branch_name)
      return { changed: [], committed: false, merged: false, branch: branch_name }
    end

    run_git!(root, "add", "--", *changed)
    run_git!(root, "-c", "user.name=Plastic", "-c", "user.email=plastic@localhost",
             "commit", "--quiet", "-m", commit_message)
    checkout!(root, base)
    run_git!(root, "merge", "--quiet", "--no-ff", "-m", "Merge #{branch_name} into #{base}", branch_name)
    delete_branch(root, branch_name)

    { changed: changed, committed: true, merged: true, branch: branch_name }
  end

  def checkout!(root, ref)
    run_git!(root, "checkout", "--quiet", ref)
  end

  def delete_branch(root, name)
    Open3.capture3("git", "-C", root, "branch", "--quiet", "-D", name)
  end

  def run_git!(root, *args)
    _out, err, status = Open3.capture3("git", "-C", root, *args)
    raise "git #{args.join(" ")} failed in #{root}: #{err}" unless status.success?
  end
end
```

## 8b. Tests - new file `test/maintenance_git_test.rb`

```ruby
# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"

require_relative "../scripts/lib/maintenance_git"

class MaintenanceGitTest < Minitest::Test
  def setup
    @repo = Dir.mktmpdir("plastic-maintenance-git")
    Open3.capture3("git", "-C", @repo, "init", "-q", "-b", "main")
    File.write(File.join(@repo, "seed.md"), "seed\n")
    Open3.capture3("git", "-C", @repo, "add", "seed.md")
    Open3.capture3("git", "-C", @repo, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "seed")
  end

  def teardown
    FileUtils.remove_entry(@repo) if @repo && Dir.exist?(@repo)
  end

  def branches
    out, = Open3.capture3("git", "-C", @repo, "branch", "--list")
    out.lines.map { |l| l.sub("*", "").strip }
  end

  def test_runs_block_and_merges_scoped_change_back_to_main
    result = MaintenanceGit.run_scoped(repo_dir: @repo, branch_name: "maintenance/t1",
                                       commit_message: "chore: t1") do
      File.write(File.join(@repo, "new.md"), "new\n")
    end

    assert_equal ["new.md"], result[:changed]
    assert result[:committed]
    assert result[:merged]

    out, = Open3.capture3("git", "-C", @repo, "rev-parse", "--abbrev-ref", "HEAD")
    assert_equal "main", out.strip
    assert File.exist?(File.join(@repo, "new.md"))
    refute_includes branches, "maintenance/t1", "the maintenance branch must be deleted after merge"

    status_out, = Open3.capture3("git", "-C", @repo, "status", "--porcelain")
    assert_empty status_out.strip
  end

  def test_refuses_to_start_when_working_tree_is_dirty
    File.write(File.join(@repo, "unrelated.md"), "dirty\n")

    assert_raises(MaintenanceGit::DirtyWorkingTree) do
      MaintenanceGit.run_scoped(repo_dir: @repo, branch_name: "maintenance/t2",
                                 commit_message: "chore: t2") { flunk "block must never run" }
    end

    refute_includes branches, "maintenance/t2", "no branch should be created on refusal"
  end

  # FALSIFIABLE (208): a no-op block must not fabricate a commit or leave a branch behind.
  def test_noop_block_makes_no_commit_and_deletes_branch
    before_log, = Open3.capture3("git", "-C", @repo, "log", "--oneline")

    result = MaintenanceGit.run_scoped(repo_dir: @repo, branch_name: "maintenance/t3",
                                       commit_message: "chore: t3") { } # no-op

    refute result[:committed]
    refute result[:merged]
    assert_empty result[:changed]
    after_log, = Open3.capture3("git", "-C", @repo, "log", "--oneline")
    assert_equal before_log, after_log, "a no-op run must add zero commits"
    refute_includes branches, "maintenance/t3"
  end

  # FALSIFIABLE (208): an error mid-block must restore a clean main with no orphaned branch
  # and no partial file left over, proving the clean-tree precondition made recovery safe.
  def test_error_in_block_restores_clean_main_and_deletes_branch
    assert_raises(RuntimeError) do
      MaintenanceGit.run_scoped(repo_dir: @repo, branch_name: "maintenance/t4",
                                 commit_message: "chore: t4") do
        File.write(File.join(@repo, "partial.md"), "oops\n")
        raise "boom"
      end
    end

    out, = Open3.capture3("git", "-C", @repo, "rev-parse", "--abbrev-ref", "HEAD")
    assert_equal "main", out.strip
    status_out, = Open3.capture3("git", "-C", @repo, "status", "--porcelain")
    assert_empty status_out.strip, "the working tree must be clean after a failed maintenance attempt"
    refute File.exist?(File.join(@repo, "partial.md"))
    refute_includes branches, "maintenance/t4"
  end

  def test_not_a_git_repo_raises_before_touching_anything
    plain_dir = Dir.mktmpdir("plastic-not-a-repo")
    begin
      assert_raises(MaintenanceGit::NotAGitRepo) do
        MaintenanceGit.run_scoped(repo_dir: plain_dir, branch_name: "x", commit_message: "x") { }
      end
    ensure
      FileUtils.remove_entry(plain_dir)
    end
  end
end
```

## Verify

`ruby -Itest test/maintenance_git_test.rb` green, then the full suite.
