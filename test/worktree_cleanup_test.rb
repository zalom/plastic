# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "stringio"
require_relative "../scripts/lib/worktree"

# Hermetic tests for the CLEANUP policy layered on Worktree (intent 73c3):
# the merge-vs-remove `finish`, and the `ensure_gitignored` safety helper. No
# real git runs: a FakeRunner records calls and returns scripted results.
class WorktreeCleanupTest < Minitest::Test
  # A fake ShellRunner. Records every `run(*args)` and returns a scripted
  # Result. By default every git call "succeeds"; tests override per-arg.
  class FakeRunner
    attr_reader :calls

    def initialize(&block)
      @calls = []
      @responder = block
    end

    def run(*args)
      @calls << args.map(&:to_s)
      r = @responder ? @responder.call(args.map(&:to_s)) : nil
      r || Worktree::ShellRunner::Result.new(0, "main\n", "")
    end
  end

  def setup
    @home = Dir.mktmpdir("wtc-home")
    @plastic_home = File.join(@home, ".plastic")
    FileUtils.mkdir_p(@plastic_home)
    @repo = File.join(@home, "apps", "demo")
    FileUtils.mkdir_p(@repo)
    write_projects("demo" => @repo)
    @store = File.join(@plastic_home, "projects", "demo", "store")
    FileUtils.mkdir_p(@store)
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def write_projects(map)
    body = { "projects" => map.transform_values { |p| { "path" => p } } }
    File.write(File.join(@plastic_home, "projects.yml"), body.to_yaml)
  end

  def provisioned_bridge(id: "73c3", slug: "cleanup")
    {
      "intent" => { "id" => id, "dir" => "#{id}--#{slug}", "store" => @store, "name" => slug },
      "worktree" => {
        "code" => File.join(@repo, ".claude", "worktrees", "#{id}--#{slug}"),
        "code_branch" => "plastic/#{id}--#{slug}",
        "provisioned" => true,
      },
    }
  end

  # --- finish: merge-then-remove (releasing path) ----------------------------

  def test_finish_merge_merges_branch_before_removing
    runner = FakeRunner.new do |args|
      # current branch resolution -> "main" (the integration target)
      if args[2] == "rev-parse"
        next Worktree::ShellRunner::Result.new(0, "main\n", "")
      end
      Worktree::ShellRunner::Result.new(0, "", "")
    end

    result = Worktree.finish(provisioned_bridge, home: @home, runner: runner, merge: true)
    assert_nil result["worktree"], "worktree block must be cleared"

    merge = runner.calls.find { |c| c.include?("merge") && c.include?("plastic/73c3--cleanup") }
    refute_nil merge, "the code branch must be merged"
    assert_equal "-C", merge[0]
    assert_equal @repo, merge[1]
    assert_includes merge, "--no-ff"

    # Merge must happen BEFORE the code worktree removal.
    merge_idx = runner.calls.index(merge)
    code_remove = runner.calls.index do |c|
      c.include?("remove") && c.include?(File.join(@repo, ".claude", "worktrees", "73c3--cleanup"))
    end
    refute_nil code_remove
    assert merge_idx < code_remove, "merge must precede worktree removal"

    # And both worktrees were removed + pruned.
    assert_equal 1, runner.calls.count { |c| c.include?("remove") }
    refute_empty runner.calls.select { |c| c.include?("prune") }
  end

  def test_finish_merge_fail_open_on_conflict_aborts_and_still_removes
    runner = FakeRunner.new do |args|
      next Worktree::ShellRunner::Result.new(0, "main\n", "") if args[2] == "rev-parse"
      # The merge itself fails (conflict).
      if args[2] == "merge" && args.include?("plastic/73c3--cleanup")
        next Worktree::ShellRunner::Result.new(1, "", "CONFLICT (content)")
      end
      Worktree::ShellRunner::Result.new(0, "", "")
    end

    out = capture_stderr do
      result = Worktree.finish(provisioned_bridge, home: @home, runner: runner, merge: true)
      assert_nil result["worktree"]
    end
    refute_empty out

    # A failed merge is aborted, and teardown still happens (worktree not stranded).
    assert runner.calls.any? { |c| c.include?("merge") && c.include?("--abort") }, "must abort failed merge"
    assert_equal 1, runner.calls.count { |c| c.include?("remove") }
  end

  def test_finish_merge_skips_when_target_equals_code_branch
    # current branch IS the code branch -> nothing to merge into.
    runner = FakeRunner.new do |args|
      if args[2] == "rev-parse"
        next Worktree::ShellRunner::Result.new(0, "plastic/73c3--cleanup\n", "")
      end
      Worktree::ShellRunner::Result.new(0, "", "")
    end
    Worktree.finish(provisioned_bridge, home: @home, runner: runner, merge: true)
    refute runner.calls.any? { |c| c.include?("merge") && !c.include?("--abort") },
           "must not merge a branch into itself"
    # Still removes.
    assert_equal 1, runner.calls.count { |c| c.include?("remove") }
  end

  # --- finish: remove-only (disarm / abandon path) ---------------------------

  def test_finish_remove_only_does_not_merge
    runner = FakeRunner.new
    result = Worktree.finish(provisioned_bridge, home: @home, runner: runner, merge: false)
    assert_nil result["worktree"]
    refute runner.calls.any? { |c| c.include?("merge") }, "remove-only must not merge"
    assert_equal 1, runner.calls.count { |c| c.include?("remove") }
    refute_empty runner.calls.select { |c| c.include?("prune") }
  end

  def test_finish_default_is_remove_only
    runner = FakeRunner.new
    Worktree.finish(provisioned_bridge, home: @home, runner: runner)
    refute runner.calls.any? { |c| c.include?("merge") }, "default finish must not merge"
  end

  # --- finish: idempotent / no-op when nothing provisioned -------------------

  def test_finish_noop_when_no_worktree_block
    runner = FakeRunner.new
    data = { "intent" => { "id" => "73c3", "store" => @store } } # no worktree key
    result = Worktree.finish(data, home: @home, runner: runner, merge: true)
    assert_empty runner.calls
    assert_nil result["worktree"]
  end

  def test_finish_noop_for_non_hash
    assert_nil Worktree.finish(nil)
    assert_equal "x", Worktree.finish("x")
  end

  def test_finish_idempotent_second_call_is_noop
    runner = FakeRunner.new
    data = provisioned_bridge
    Worktree.finish(data, home: @home, runner: runner, merge: false)
    runner.calls.clear
    # Block already cleared; a second finish does nothing.
    Worktree.finish(data, home: @home, runner: runner, merge: false)
    assert_empty runner.calls
  end

  # --- ensure_gitignored: appends once, idempotent ---------------------------

  def test_ensure_gitignored_appends_entry_when_absent
    assert Worktree.ensure_gitignored(@repo, ".claude/worktrees/", runner: FakeRunner.new)
    gitignore = File.join(@repo, ".gitignore")
    assert File.exist?(gitignore)
    assert_includes File.read(gitignore), ".claude/worktrees/"
  end

  def test_ensure_gitignored_idempotent_does_not_duplicate
    3.times { Worktree.ensure_gitignored(@repo, ".worktrees/", runner: FakeRunner.new) }
    count = File.read(File.join(@repo, ".gitignore")).each_line.count { |l| l.strip == ".worktrees/" }
    assert_equal 1, count, "entry must appear exactly once"
  end

  def test_ensure_gitignored_preserves_existing_content
    gitignore = File.join(@repo, ".gitignore")
    File.write(gitignore, "node_modules/\n*.log\n")
    Worktree.ensure_gitignored(@repo, ".claude/worktrees/", runner: FakeRunner.new)
    body = File.read(gitignore)
    assert_includes body, "node_modules/"
    assert_includes body, "*.log"
    assert_includes body, ".claude/worktrees/"
  end

  def test_ensure_gitignored_adds_trailing_newline_when_missing
    gitignore = File.join(@repo, ".gitignore")
    File.write(gitignore, "node_modules/") # no trailing newline
    Worktree.ensure_gitignored(@repo, ".worktrees/", runner: FakeRunner.new)
    lines = File.read(gitignore).each_line.map(&:strip)
    assert_includes lines, "node_modules/"
    assert_includes lines, ".worktrees/"
  end

  def test_ensure_gitignored_noop_for_blank_or_missing_repo
    refute Worktree.ensure_gitignored(nil, ".worktrees/", runner: FakeRunner.new)
    refute Worktree.ensure_gitignored(@repo, "", runner: FakeRunner.new)
    refute Worktree.ensure_gitignored(File.join(@home, "does-not-exist"), ".worktrees/", runner: FakeRunner.new)
  end

  # --- provision calls ensure_gitignored -------------------------------------

  # Intent 178 retired the store worktree, so provision no longer ensures a
  # `.worktrees/` entry in the plastic home's own `.gitignore` (that entry
  # already ships committed there from prior runs and is left alone). The code
  # repo's `.gitignore` entry is unaffected: the code worktree stays mandatory.
  def test_provision_ensures_the_code_repo_gitignore_entry
    runner = FakeRunner.new do |args|
      if args[2] == "rev-parse"
        next Worktree::ShellRunner::Result.new(0, "true\n", "")
      end
      Worktree::ShellRunner::Result.new(0, "", "")
    end
    bridge = {
      "intent" => { "id" => "73c3", "dir" => "73c3--cleanup", "store" => @store, "name" => "cleanup" },
    }
    Worktree.provision(bridge, home: @home, runner: runner)

    assert_includes File.read(File.join(@repo, ".gitignore")), ".claude/worktrees/"
    refute_includes File.read(File.join(@plastic_home, ".gitignore")), ".worktrees/",
      "provision no longer writes a .worktrees/ entry into the plastic home gitignore (intent 178)"
  end

  def capture_stderr
    original = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = original
  end
end
