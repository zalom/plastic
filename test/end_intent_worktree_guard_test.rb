# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "json"
require "yaml"
require "rbconfig"
require_relative "../scripts/lib/bridge"
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
               { "projects" => { "demo" => { "path" => @repo } } }.to_yaml)
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def run_end_intent(*args, session:)
    env = { "CLAUDE_CODE_SESSION_ID" => nil, "HOME" => @home, "PLASTIC_TMP" => @tmp_bridge }
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

  def write_bridge(session:, id:, slug: "demo", worktree_code:)
    data = {
      "session" => session,
      "intent" => { "id" => id, "dir" => "#{id}--#{slug}", "store" => @store, "name" => slug },
      "build" => { "auto" => false },
      "worktree" => {
        "code" => worktree_code, "code_branch" => "plastic/#{id}--#{slug}",
        "store" => nil, "store_branch" => nil, "provisioned" => true,
      },
      "lock" => { "owner_session" => session, "acquired_at" => Time.now.utc.iso8601,
                  "host" => "test", "type" => "delivery", "delegates" => [] },
    }
    File.write(File.join(@tmp_bridge, "plastic-#{session}--#{id}.json"), JSON.pretty_generate(data))
  end

  # --- AC11: dirty worktree refuses; --discard-worktree-changes overrides ----

  def test_ac11_dirty_worktree_refuses_then_discard_flag_overrides
    id = "161"
    intent_dir = build_intent(id: id)
    write_index(id: id)
    Lock.acquire(intent_dir, session: "sess-1")
    worktree_path = build_worktree(id: id)
    File.write(File.join(worktree_path, "scratch.txt"), "uncommitted\n")
    write_bridge(session: "sess-1", id: id, worktree_code: worktree_path)

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

    not_a_repo = File.join(@home, "not-a-git-repo")
    FileUtils.mkdir_p(not_a_repo)
    marker = File.join(not_a_repo, "scratch.txt")
    File.write(marker, "uncommitted work that must survive\n")
    write_bridge(session: "sess-1", id: id, worktree_code: not_a_repo)

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
    data = {
      "session" => "sess-1",
      "intent" => { "id" => id, "dir" => "#{id}--demo", "store" => @store, "name" => "demo" },
      "lock" => { "owner_session" => "sess-1" },
    }
    File.write(File.join(@tmp_bridge, "plastic-sess-1--#{id}.json"), JSON.pretty_generate(data))

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
    gone_path = File.join(@repo, ".claude", "worktrees", "#{id}--demo") # never created on disk
    write_bridge(session: "sess-1", id: id, worktree_code: gone_path)

    _out, status = run_end_intent("--store", @store, "--id", id, "--disposition", "delivered",
                                   "--index", @index, "--no-commit", session: "sess-1")
    assert_equal 0, status
    refute File.exist?(Lock.path(intent_dir))
  end
end
