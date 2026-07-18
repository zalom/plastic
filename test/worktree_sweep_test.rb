# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/worktree_sweep"

class WorktreeSweepTest < Minitest::Test
  class FakeRunner
    attr_reader :calls
    def initialize(&block)
      @calls = []
      @responder = block
    end

    def run(*args)
      @calls << args.map(&:to_s)
      r = @responder ? @responder.call(args.map(&:to_s)) : nil
      r || Worktree::ShellRunner::Result.new(0, "", "")
    end
  end

  def setup
    @home = Dir.mktmpdir("sweep-home")
    @plastic_home = File.join(@home, ".plastic")
    @wt_dir = File.join(@plastic_home, ".worktrees")
    FileUtils.mkdir_p(@wt_dir)
    @global_store = File.join(@plastic_home, "store")
    FileUtils.mkdir_p(@global_store)
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def write_index(store, entries)
    # entries: [[section, id_dash_slug, title], ...]
    body = +"# Index\n\n"
    %w[Active Future Completed Abandoned].each do |section|
      body << "## #{section}\n"
      rows = entries.select { |e| e[0] == section }
      if rows.empty?
        body << "_(none)_\n\n"
      else
        rows.each { |(_, name, title)| body << "- [#{name.split('--').first} — #{title}](store/#{name}/#{name}.md)\n" }
        body << "\n"
      end
    end
    File.write(File.join(File.dirname(store), "INDEX.md"), body)
  end

  def make_intent_dir(store, name)
    FileUtils.mkdir_p(File.join(store, name))
  end

  def make_worktree(name)
    FileUtils.mkdir_p(File.join(@wt_dir, name))
  end

  def runner_with_ahead_counts(counts)
    FakeRunner.new do |args|
      if args[2] == "rev-parse"
        next Worktree::ShellRunner::Result.new(0, "main\n", "")
      end
      if args[2] == "rev-list"
        branch = args.last.split("..").last
        count = counts.fetch(branch, 0)
        next Worktree::ShellRunner::Result.new(0, "#{count}\n", "")
      end
      Worktree::ShellRunner::Result.new(0, "", "")
    end
  end

  # --- the D6 falsifiable test: an ahead-of-main branch is always spared,
  # --- even when the intent is terminal -----------------------------------

  def test_sweep_spares_terminal_intent_whose_branch_is_ahead_of_main
    name = "197--separate-maintenance-from-work"
    make_intent_dir(@global_store, name)
    make_worktree(name)
    write_index(@global_store, [["Completed", name, "Separate maintenance from work"]])

    runner = runner_with_ahead_counts({ "plastic-store/#{name}" => 3 })
    candidates = WorktreeSweep.candidates(plastic_home: @plastic_home, runner: runner)

    c = candidates.find { |x| x.name == name }
    refute_nil c
    assert_equal :spare, c.decision,
      "a terminal intent's worktree must still be spared when its branch carries commits ahead of main"
    assert_match(/ahead of main/, c.reason)

    # Prove the test can fail: the SAME setup but 0 commits ahead removes it.
    runner2 = runner_with_ahead_counts({ "plastic-store/#{name}" => 0 })
    candidates2 = WorktreeSweep.candidates(plastic_home: @plastic_home, runner: runner2)
    c2 = candidates2.find { |x| x.name == name }
    assert_equal :remove, c2.decision,
      "sanity check: the same terminal intent IS eligible once its branch is not ahead"
  end

  # --- terminal + not ahead => remove ---------------------------------------

  def test_sweep_marks_terminal_not_ahead_worktree_for_removal
    name = "1--monetize-dealintell"
    make_intent_dir(@global_store, name)
    make_worktree(name)
    write_index(@global_store, [["Completed", name, "Monetize dealintell"]])

    candidates = WorktreeSweep.candidates(plastic_home: @plastic_home,
                                          runner: runner_with_ahead_counts({}))
    c = candidates.find { |x| x.name == name }
    assert_equal :remove, c.decision
    assert_equal "Completed", c.status
    assert_equal 0, c.ahead_count
  end

  # --- non-terminal (still Active) is spared, regardless of branch ---------

  def test_sweep_spares_active_intent_even_when_not_ahead
    name = "178--store-worktrees-wire-or-retire"
    make_intent_dir(@global_store, name)
    make_worktree(name)
    write_index(@global_store, [["Active", name, "Store worktrees"]])

    candidates = WorktreeSweep.candidates(plastic_home: @plastic_home,
                                          runner: runner_with_ahead_counts({}))
    c = candidates.find { |x| x.name == name }
    assert_equal :spare, c.decision
    assert_match(/not terminal/, c.reason)
  end

  # --- no matching intent directory anywhere: spared, never guessed --------

  def test_sweep_spares_when_no_intent_directory_resolves
    name = "999--long-gone"
    make_worktree(name) # worktree dir exists, but no intent dir anywhere

    candidates = WorktreeSweep.candidates(plastic_home: @plastic_home,
                                          runner: runner_with_ahead_counts({}))
    c = candidates.find { |x| x.name == name }
    assert_equal :spare, c.decision
    assert_nil c.intent_dir
    assert_match(/no matching intent directory/, c.reason)
  end

  # --- project-store resolution (not just the global store) ----------------

  def test_sweep_resolves_intent_in_a_project_store
    name = "63--mihradesign-thing"
    project_store = File.join(@plastic_home, "projects", "mihradesign", "store")
    FileUtils.mkdir_p(project_store)
    make_intent_dir(project_store, name)
    make_worktree(name)
    write_index(project_store, [["Completed", name, "Mihradesign thing"]])

    candidates = WorktreeSweep.candidates(plastic_home: @plastic_home,
                                          runner: runner_with_ahead_counts({}))
    c = candidates.find { |x| x.name == name }
    assert_equal :remove, c.decision
    assert_equal project_store, File.dirname(c.intent_dir)
  end

  # --- dry_run_report: lists every candidate, removes nothing ---------------

  def test_dry_run_report_lists_all_candidates_and_removes_nothing
    name = "1--monetize-dealintell"
    make_intent_dir(@global_store, name)
    make_worktree(name)
    write_index(@global_store, [["Completed", name, "Monetize dealintell"]])

    candidates = WorktreeSweep.candidates(plastic_home: @plastic_home,
                                          runner: runner_with_ahead_counts({}))
    report = WorktreeSweep.dry_run_report(candidates)
    assert_match(/REMOVE.*#{Regexp.escape(name)}/, report)
    assert_match(/1 of 1 candidate/, report)
    assert Dir.exist?(File.join(@wt_dir, name)), "dry run must never remove anything"
  end

  # --- apply!: removes only :remove candidates, via git worktree remove/prune -

  def test_apply_removes_only_remove_candidates_via_worktree_remove_and_prunes
    keep_name = "178--store-worktrees-wire-or-retire"
    drop_name = "1--monetize-dealintell"
    make_intent_dir(@global_store, keep_name)
    make_worktree(keep_name)
    make_intent_dir(@global_store, drop_name)
    make_worktree(drop_name)
    write_index(@global_store, [
      ["Active", keep_name, "Store worktrees"],
      ["Completed", drop_name, "Monetize dealintell"],
    ])

    runner = runner_with_ahead_counts({})
    candidates = WorktreeSweep.candidates(plastic_home: @plastic_home, runner: runner)
    removed = WorktreeSweep.apply!(candidates, plastic_home: @plastic_home, runner: runner)

    assert_equal [drop_name], removed.map(&:name)
    remove_calls = runner.calls.select { |c| c.include?("remove") }
    assert_equal 1, remove_calls.length
    assert_includes remove_calls.first, File.join(@wt_dir, drop_name)
    refute(remove_calls.any? { |c| c.include?(File.join(@wt_dir, keep_name)) })
    assert runner.calls.any? { |c| c.include?("prune") }, "apply! must prune after removing"
  end

  def test_apply_prunes_nothing_when_nothing_removed
    name = "178--store-worktrees-wire-or-retire"
    make_intent_dir(@global_store, name)
    make_worktree(name)
    write_index(@global_store, [["Active", name, "Store worktrees"]])

    runner = runner_with_ahead_counts({})
    candidates = WorktreeSweep.candidates(plastic_home: @plastic_home, runner: runner)
    removed = WorktreeSweep.apply!(candidates, plastic_home: @plastic_home, runner: runner)

    assert_empty removed
    refute runner.calls.any? { |c| c.include?("remove") }
    refute runner.calls.any? { |c| c.include?("prune") },
      "apply! must not even prune when there was nothing to remove"
  end
end
