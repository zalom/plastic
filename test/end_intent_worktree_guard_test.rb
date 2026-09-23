# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "json"
require "yaml"
require "rbconfig"
require_relative "../scripts/lib/lock"

# end-intent step 5's dirty-worktree guard (intent 188, D16, AC11/AC12). A
# separate file from test/end_intent_test.rb: these fixtures need a REAL git
# repo plus a REAL registered worktree (so Worktree.release's actual `git
# worktree remove` can be exercised and verified), which needs the
# subprocess's HOME env pointed at a sandboxed ~/.plastic (projects.yml plus a
# real repo), on top of the PLASTIC_TMP bridge isolation every end-intent
# subprocess test needs. test/hermeticity_guard_test.rb is a STATIC source
# scan and cannot see a subprocess's env, so isolate defensively regardless.
class EndIntentWorktreeGuardTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/end-intent", __dir__)

  def setup
    @home = Dir.mktmpdir("end-intent-wtguard-home") # this IS HOME for the subprocess
    @plastic_home = File.join(@home, ".plastic")
    FileUtils.mkdir_p(@plastic_home)
    @tmp_bridge = File.join(@home, "bridge-tmp") # this IS PLASTIC_TMP for the subprocess
    FileUtils.mkdir_p(@tmp_bridge)

    @store = File.join(@plastic_home, "projects", "demo", "store")
    FileUtils.mkdir_p(@store)
    @index = File.join(File.dirname(@store), "INDEX.md")

    @repo = File.join(@home, "code-repo")
    FileUtils.mkdir_p(@repo)
    Open3.capture3("git", "init", "-q", @repo)
    Open3.capture3("git", "-C", @repo, "-c", "user.email=t@t.test", "-c", "user.name=Test",
      "commit", "--allow-empty", "-q", "-m", "init")
    File.write(File.join(@plastic_home, "projects.yml"),
      {"projects" => {"demo" => {"path" => @repo}}}.to_yaml)
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def run_end_intent(*args, session:)
    env = {"CLAUDE_CODE_SESSION_ID" => nil, "HOME" => @home, "PLASTIC_TMP" => @tmp_bridge}
    argv = args + ["--session", session]
    out = IO.popen(env, [RbConfig.ruby, SCRIPT, *argv], err: [:child, :out], &:read)
    [out.strip, $?.exitstatus]
  end

  def build_intent(id: "161", slug: "demo")
    intent_dir = File.join(@store, "#{id}--#{slug}")
    FileUtils.mkdir_p(intent_dir)
    File.write(File.join(intent_dir, "#{id}--#{slug}.md"), <<~MD)
      ---
      id: "#{id}"
      intent: "Demo intent"
      sources: []
      chain: []
      created: 2026-07-01
      author: human
      tags: []
      ---

      ## Intent
      Demo intent

      ## Context

      ## Outcome
      (the result)

      ## Insights

      ## Links
      <!-- No sources or chain; this intent has no graph edges to project. -->
    MD
    File.write(File.join(intent_dir, "outcome.md"), <<~MD)
      ---
      disposition: delivered
      ---
      # Outcome: Demo intent

      ## Summary
      Did the thing.
    MD
    # Real, complete spec/plan/checklist (intent 222): the per-intent structure gate now
    # runs ahead of the dirty-worktree guard too, so a fixture exercising that guard must
    # otherwise present a clean, fully delivered intent.
    File.write(File.join(intent_dir, "spec.md"), "# Spec: Demo intent\n")
    File.write(File.join(intent_dir, "plan.md"), "# Plan: Demo intent\n\n- [x] Step 1\n")
    File.write(File.join(intent_dir, "checklist.md"), "# Checklist: Demo intent\n\n- [x] Step 1\n")
    intent_dir
  end

  def write_index(id: "161", slug: "demo")
    File.write(@index, <<~MD)
      # Index

      ## Active
      - [#{id} — Demo intent](store/#{id}--#{slug}/#{id}--#{slug}.md) — a demo intent for the test suite

      ## Completed
      _(none)_

      ## Abandoned
      _(none)_
    MD
  end

  def build_worktree(id:, slug: "demo")
    path = File.join(@repo, ".claude", "worktrees", "#{id}--#{slug}")
    FileUtils.mkdir_p(File.dirname(path))
    Open3.capture3("git", "-C", @repo, "worktree", "add", path, "-b", "plastic/#{id}--#{slug}")
    path
  end

  # --- AC11: dirty worktree refuses; --discard-worktree-changes overrides ----

  def test_ac11_dirty_worktree_refuses_then_discard_flag_overrides
    id = "161"
    intent_dir = build_intent(id: id)
    write_index(id: id)
    Lock.acquire(intent_dir, session: "sess-1")
    worktree_path = build_worktree(id: id)
    File.write(File.join(worktree_path, "scratch.txt"), "uncommitted\n")

    out, status = run_end_intent("--store", @store, "--id", id, "--disposition", "delivered",
      "--index", @index, "--no-commit", session: "sess-1")
    assert_equal 5, status
    assert_match(/uncommitted/i, out)
    assert Dir.exist?(worktree_path), "the worktree must still exist on disk"
    assert File.exist?(File.join(worktree_path, "scratch.txt")), "the uncommitted change must survive intact"
    assert File.exist?(Lock.path(intent_dir)), "disarm never ran: the delivery lock must still be present"

    out2, status2 = run_end_intent("--store", @store, "--id", id, "--disposition", "delivered",
      "--index", @index, "--no-commit", "--discard-worktree-changes",
      session: "sess-1")
    assert_equal 0, status2, out2
    refute Dir.exist?(worktree_path), "--discard-worktree-changes must allow the worktree to be removed"
    refute File.exist?(Lock.path(intent_dir)), "a real close must clear the delivery lock"
  end

  # --- BLOCKER 1 (post-review, data loss): an inconclusive `git status` must --
  # --- fail CLOSED, never open. This is the most important test in this file. --
  #
  # Before the fix, `dirty = status.success? && !out.strip.empty?` made a
  # FAILED `git status --porcelain` (non-zero exit: not a git repo, corrupt
  # index, git missing) read as `dirty = false`, so the guard concluded
  # "clean" and proceeded to force-remove the worktree, permanently
  # destroying whatever uncommitted work was in it, and still exited 0. A
  # directory that is not a git repository at all is the simplest real
  # reproduction: `git -C <dir> status --porcelain` fails outright.
  def test_blocker1_worktree_whose_git_status_fails_is_never_removed_uncommitted_file_survives
    id = "161"
    intent_dir = build_intent(id: id)
    write_index(id: id)
    Lock.acquire(intent_dir, session: "sess-1")

    # The derived worktree path (projects.yml plus the intent id) exists on disk but is
    # not a git worktree at all, so `git status` there fails outright.
    not_a_repo = File.join(@repo, ".claude", "worktrees", "#{id}--demo")
    FileUtils.mkdir_p(not_a_repo)
    # A `.git` file pointing at a gitdir that does not exist makes `git status` fail
    # outright inside this directory, which is the inconclusive case the guard must refuse.
    File.write(File.join(not_a_repo, ".git"), "gitdir: #{File.join(@home, "no-such-gitdir")}\n")
    marker = File.join(not_a_repo, "scratch.txt")
    File.write(marker, "uncommitted work that must survive\n")

    out, status = run_end_intent("--store", @store, "--id", id, "--disposition", "delivered",
      "--index", @index, "--no-commit", session: "sess-1")
    assert_equal 5, status, "an inconclusive git status must refuse (exit 5), not proceed: #{out}"
    assert_match(/could not inspect/i, out)
    assert Dir.exist?(not_a_repo), "BLOCKER 1: the worktree directory must NOT be removed"
    assert File.exist?(marker), "BLOCKER 1: the uncommitted file must survive intact"
    assert_equal "uncommitted work that must survive\n", File.read(marker)
    assert File.exist?(Lock.path(intent_dir)), "disarm never ran: the delivery lock must still be present"
  end

  # --- AC12: no worktree block, and an already-gone worktree, are clean no-ops --

  def test_ac12_no_worktree_block_does_not_raise
    id = "161"
    intent_dir = build_intent(id: id)
    write_index(id: id)
    Lock.acquire(intent_dir, session: "sess-1")
    # No worktree directory exists for this intent, so the derived block is empty.

    _out, status = run_end_intent("--store", @store, "--id", id, "--disposition", "delivered",
      "--index", @index, "--no-commit", session: "sess-1")
    assert_equal 0, status
    refute File.exist?(Lock.path(intent_dir))
  end

  def test_ac12_already_removed_worktree_directory_does_not_raise
    id = "161"
    intent_dir = build_intent(id: id)
    write_index(id: id)
    Lock.acquire(intent_dir, session: "sess-1")
    File.join(@repo, ".claude", "worktrees", "#{id}--demo") # never created on disk

    _out, status = run_end_intent("--store", @store, "--id", id, "--disposition", "delivered",
      "--index", @index, "--no-commit", session: "sess-1")
    assert_equal 0, status
    refute File.exist?(Lock.path(intent_dir))
  end

  # --- A delivered close refuses unmerged code (exit 9), before any write ----

  def git(*args)
    out, _err, _st = Open3.capture3("git", "-c", "user.email=t@t.test", "-c", "user.name=Test", *args)
    out.strip
  end

  def commit_in(path, file, body)
    File.write(File.join(path, file), body)
    git("-C", path, "add", file)
    git("-C", path, "commit", "-q", "-m", "work on #{file}")
  end

  # Everything an unmerged close must leave alone: INDEX, savepoint, lock,
  # worktree, and both git heads.
  def close_state(intent_dir, worktree_path)
    savepoint = File.join(intent_dir, "savepoint.md")
    [File.binread(@index), File.exist?(savepoint) && File.binread(savepoint),
      File.binread(Lock.path(intent_dir)), Dir.exist?(worktree_path),
      git("-C", @repo, "rev-parse", "HEAD"), git("-C", worktree_path, "rev-parse", "HEAD"),
      Dir.children(intent_dir).sort]
  end

  def unmerged_fixture
    intent_dir = build_intent(id: "161")
    write_index(id: "161")
    Lock.acquire(intent_dir, session: "sess-1")
    worktree_path = build_worktree(id: "161")
    commit_in(worktree_path, "feature.rb", "puts 1\n")
    [intent_dir, worktree_path]
  end

  def test_unmerged_delivered_close_refuses_before_any_write
    intent_dir, worktree_path = unmerged_fixture
    before = close_state(intent_dir, worktree_path)

    out, status = run_end_intent("--store", @store, "--id", "161", "--disposition", "delivered",
      "--index", @index, session: "sess-1")
    assert_equal 9, status, out
    assert_includes out, "git -C #{@repo} merge plastic/161--demo"
    assert_includes out, "nothing was merged, written, or released"
    assert_equal before, close_state(intent_dir, worktree_path)
    refute File.exist?(File.join(@repo, "feature.rb")), "end-intent must never merge"
  end

  def test_unmerged_delivered_dry_run_refuses_the_same_way
    intent_dir, worktree_path = unmerged_fixture
    before = close_state(intent_dir, worktree_path)

    out, status = run_end_intent("--store", @store, "--id", "161", "--disposition", "delivered",
      "--index", @index, "--dry-run", session: "sess-1")
    assert_equal 9, status, out
    assert_includes out, "dry run: would refuse a delivered close"
    assert_includes out, "git -C #{@repo} merge plastic/161--demo"
    assert_equal before, close_state(intent_dir, worktree_path)
  end

  def test_already_merged_delivered_close_succeeds
    intent_dir, worktree_path = unmerged_fixture
    git("-C", @repo, "merge", "-q", "--no-edit", "plastic/161--demo")

    out, status = run_end_intent("--store", @store, "--id", "161", "--disposition", "delivered",
      "--index", @index, "--no-commit", session: "sess-1")
    assert_equal 0, status, out
    refute Dir.exist?(worktree_path)
    refute File.exist?(Lock.path(intent_dir))
    assert_match(/## Completed\n- \[161/, File.read(@index))
  end

  def test_abandoned_close_releases_without_merging
    id = "161"
    intent_dir = build_intent(id: id)
    File.write(File.join(intent_dir, "outcome.md"), "---\ndisposition: abandoned\n---\n# Outcome: Demo intent\n\n## Summary\nDropped.\n")
    write_index(id: id)
    Lock.acquire(intent_dir, session: "sess-1")
    worktree_path = build_worktree(id: id)
    commit_in(worktree_path, "feature.rb", "puts 1\n")
    main_head = git("-C", @repo, "rev-parse", "HEAD")

    out, status = run_end_intent("--store", @store, "--id", id, "--disposition", "abandoned",
      "--index", @index, "--no-commit", session: "sess-1")
    assert_equal 0, status, out
    assert_equal main_head, git("-C", @repo, "rev-parse", "HEAD"), "an abandoned close must not merge"
    refute File.exist?(Lock.path(intent_dir))
  end

  # A real worktree must prove its HEAD commit merged, whatever branch it is on,
  # and a close must refuse before it writes anything.
  def assert_refused_unchanged(intent_dir, worktree_path, expected)
    before = close_state(intent_dir, worktree_path)
    out, status = run_end_intent("--store", @store, "--id", "161", "--disposition", "delivered",
      "--index", @index, "--no-commit", session: "sess-1")
    assert_equal 9, status, out
    expected.each { |text| assert_includes out, text }
    assert_equal before, close_state(intent_dir, worktree_path)
  end

  def test_detached_worktree_with_deleted_branch_refuses
    intent_dir, worktree_path = unmerged_fixture
    git("-C", worktree_path, "checkout", "-q", "--detach")
    git("-C", @repo, "branch", "-q", "-D", "plastic/161--demo")
    sha = git("-C", worktree_path, "rev-parse", "HEAD")[0, 12]

    assert_refused_unchanged(intent_dir, worktree_path,
      ["(detached at #{sha}) is not merged", "git -C #{@repo} merge #{sha}"])
  end

  def test_renamed_worktree_branch_refuses
    intent_dir, worktree_path = unmerged_fixture
    git("-C", worktree_path, "branch", "-m", "renamed-work")

    assert_refused_unchanged(intent_dir, worktree_path, ["(on branch renamed-work at", "is not merged"])
  end

  def test_unreadable_worktree_head_refuses
    intent_dir, worktree_path = unmerged_fixture
    git("-C", worktree_path, "checkout", "-q", "--orphan", "unborn")

    assert_refused_unchanged(intent_dir, worktree_path, ["could not read the HEAD commit"])
  end

  def test_removed_worktree_with_unmerged_branch_refuses
    intent_dir, worktree_path = unmerged_fixture
    git("-C", @repo, "worktree", "remove", worktree_path)

    assert_refused_unchanged(intent_dir, worktree_path,
      ["code branch plastic/161--demo is not merged", "git -C #{@repo} merge plastic/161--demo"])
  end

  def test_detached_repo_checkout_refuses
    intent_dir, worktree_path = unmerged_fixture
    git("-C", @repo, "checkout", "-q", "--detach")

    assert_refused_unchanged(intent_dir, worktree_path, ["#{@repo} is not on a branch"])
  end

  def test_repo_checkout_on_the_code_branch_refuses
    intent_dir, worktree_path = unmerged_fixture
    git("-C", @repo, "worktree", "remove", worktree_path)
    git("-C", @repo, "checkout", "-q", "plastic/161--demo")

    assert_refused_unchanged(intent_dir, worktree_path, ["is on the code branch plastic/161--demo itself"])
  end

  def test_unreadable_repository_refuses
    intent_dir, worktree_path = unmerged_fixture
    File.write(File.join(@repo, ".git", "HEAD"), "garbage\n")

    assert_refused_unchanged(intent_dir, worktree_path, ["could not inspect the Git repository #{@repo}"])
  end
end
