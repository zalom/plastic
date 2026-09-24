# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "yaml"
require "rbconfig"
require_relative "../scripts/lib/lock"

# end-intent step 5's worktree handling (intent 188, D16, AC11/AC12; rewritten
# for intent 390). Plastic runs no version control command, so a delivered
# close no longer checks the worktree for uncommitted or unmerged work: it
# only clears the delivery lock, and prints the `git worktree remove`
# instruction (from Arm.disarm) when a worktree was provisioned. No real git
# repository is built here; a plain directory under the projects.yml-declared
# repo path is enough to prove `provisioned`.
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

  def build_intent(id: "161", slug: "demo", disposition: "delivered")
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
      disposition: #{disposition}
      ---
      # Outcome: Demo intent

      ## Summary
      Did the thing.
    MD
    # Real, complete spec/plan/checklist (intent 222): the per-intent structure gate
    # runs ahead of disarm too, so a fixture exercising disarm must present a clean,
    # fully delivered intent.
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
    FileUtils.mkdir_p(path)
    path
  end

  # --- a provisioned worktree never blocks the close; the removal is printed --

  def test_delivered_close_with_a_provisioned_worktree_prints_the_removal_instruction
    id = "161"
    intent_dir = build_intent(id: id)
    write_index(id: id)
    Lock.acquire(intent_dir, session: "sess-1")
    worktree_path = build_worktree(id: id)
    File.write(File.join(worktree_path, "scratch.txt"), "uncommitted\n")

    out, status = run_end_intent("--store", @store, "--id", id, "--disposition", "delivered",
      "--index", @index, "--no-commit", session: "sess-1")
    assert_equal 0, status, out
    assert_match(/the code worktree is not removed/, out)
    assert_match(/git -C #{Regexp.escape(@repo)} worktree remove #{Regexp.escape(worktree_path)}/, out)
    assert Dir.exist?(worktree_path), "Plastic never removes the worktree itself"
    assert File.exist?(File.join(worktree_path, "scratch.txt")), "the file on disk is untouched"
    refute File.exist?(Lock.path(intent_dir)), "a real close must clear the delivery lock"
    assert_match(/## Completed\n- \[161/, File.read(@index))
  end

  def test_discard_worktree_changes_flag_is_still_accepted_and_changes_nothing
    id = "161"
    intent_dir = build_intent(id: id)
    write_index(id: id)
    Lock.acquire(intent_dir, session: "sess-1")
    worktree_path = build_worktree(id: id)

    out, status = run_end_intent("--store", @store, "--id", id, "--disposition", "delivered",
      "--index", @index, "--no-commit", "--discard-worktree-changes", session: "sess-1")
    assert_equal 0, status, out
    assert Dir.exist?(worktree_path)
    refute File.exist?(Lock.path(intent_dir))
  end

  # --- no worktree block, and an already-gone worktree, are clean no-ops -----

  def test_no_worktree_block_does_not_raise
    id = "161"
    intent_dir = build_intent(id: id)
    write_index(id: id)
    Lock.acquire(intent_dir, session: "sess-1")
    # No worktree directory exists for this intent, so the derived block is empty.

    out, status = run_end_intent("--store", @store, "--id", id, "--disposition", "delivered",
      "--index", @index, "--no-commit", session: "sess-1")
    assert_equal 0, status, out
    refute_match(/worktree remove/, out)
    refute File.exist?(Lock.path(intent_dir))
  end

  def test_abandoned_close_with_a_provisioned_worktree_also_prints_the_removal_instruction
    id = "161"
    intent_dir = build_intent(id: id, disposition: "abandoned")
    write_index(id: id)
    Lock.acquire(intent_dir, session: "sess-1")
    worktree_path = build_worktree(id: id)

    out, status = run_end_intent("--store", @store, "--id", id, "--disposition", "abandoned",
      "--index", @index, "--no-commit", session: "sess-1")
    assert_equal 0, status, out
    assert_match(/git -C #{Regexp.escape(@repo)} worktree remove #{Regexp.escape(worktree_path)}/, out)
    refute File.exist?(Lock.path(intent_dir))
  end
end
