# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require_relative "../scripts/lib/exec_worktree"
require_relative "../scripts/lib/bridge"
require_relative "../scripts/lib/lock"
require_relative "../scripts/lib/worktree"

# exec-worktree (intent 213, group 2; the order precondition left with the gates in
# intent 302): the dirty-worktree guard, then Worktree.finish. Hermetic: every fixture
# lives under Dir.mktmpdir, PLASTIC_TMP isolates the bridge dir, and no test creates,
# merges, or removes a real git worktree (the finisher seam is always injected).
# See test/worktree_test.rb and test/worktree_cleanup_test.rb for the house-style
# reference this mirrors.
class ExecWorktreeTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("exec-wt-home")
    @plastic_home = File.join(@home, ".plastic")
    FileUtils.mkdir_p(@plastic_home)
    # A project store plus projects.yml: the worktree block is derived from them
    # (intent 307), so the intent must belong to a registered project.
    @store = File.join(@plastic_home, "projects", "demo", "store")
    FileUtils.mkdir_p(@store)
    @repo = File.join(@home, "repo")
    FileUtils.mkdir_p(@repo)
    File.write(File.join(@plastic_home, "projects.yml"), "projects:\n  demo:\n    path: #{@repo}\n")

    @bridge_tmp = Dir.mktmpdir("exec-wt-bridge")
    @saved_tmp = ENV["PLASTIC_TMP"]
    ENV["PLASTIC_TMP"] = @bridge_tmp

    @session = "sess-#{Process.pid}-#{object_id}"
  end

  def teardown
    FileUtils.rm_rf(@home)
    FileUtils.rm_rf(@bridge_tmp)
    @saved_tmp.nil? ? ENV.delete("PLASTIC_TMP") : ENV["PLASTIC_TMP"] = @saved_tmp
  end

  # --- fixture builders --------------------------------------------------------------

  def build_intent_dir(id: "213", slug: "demo", how_complete: false)
    dir = File.join(@store, "#{id}--#{slug}")
    FileUtils.mkdir_p(File.join(dir, "actions"))
    File.write(File.join(dir, "#{id}--#{slug}.md"), "## Intent\nDemo\n")
    if how_complete
      File.write(File.join(dir, "plan.md"), "# Plan\nreal\n")
      File.write(File.join(dir, "checklist.md"), "# Checklist\nreal\n")
      File.write(File.join(dir, "actions", "ACTION_1.md"), "# Action 1\nreal\n")
    end
    dir
  end

  def worktree_code_path(id: "213", slug: "demo")
    File.join(@repo, ".claude", "worktrees", "#{id}--#{slug}")
  end

  class FakeStatus
    def initialize(ok)
      @ok = ok
    end

    def success?
      @ok
    end
  end

  # Fake Worktree::ShellRunner double so the post-finish merge verification (BLOCKING
  # 1/2: merged_into_current_branch? and Worktree.current_branch) never shells out to
  # real git. `ancestor: true` simulates a merge that landed cleanly (the intent branch
  # IS an ancestor of HEAD); `ancestor: false` simulates the conflicted-merge bug itself:
  # Worktree.finish already removed the worktree (fail-open), but the branch never made
  # it into the repo's history.
  class FakeRunner
    Result = Struct.new(:status, :stdout, :stderr) do
      def success?
        status.zero?
      end
    end

    def initialize(ancestor: true, current_branch: "main")
      @ancestor = ancestor
      @current_branch = current_branch
    end

    def run(*args)
      if args.include?("merge-base")
        Result.new(@ancestor ? 0 : 1, "", "")
      elsif args.include?("rev-parse")
        Result.new(0, "#{@current_branch}\n", "")
      else
        Result.new(0, "", "")
      end
    end
  end

  def merged_runner(current_branch: "main")
    FakeRunner.new(ancestor: true, current_branch: current_branch)
  end

  def unmerged_runner
    FakeRunner.new(ancestor: false)
  end

  def clean_status_checker
    ->(_worktree_code) { ["", "", FakeStatus.new(true)] }
  end

  def dirty_status_checker
    ->(_worktree_code) { ["M file.rb\n", "", FakeStatus.new(true)] }
  end

  def raising_status_checker
    ->(_worktree_code) { [nil, "git not found", nil] }
  end

  def unreachable_status_checker
    lambda do |_worktree_code|
      flunk "status_checker must not be called"
    end
  end

  # Spy finisher: records every call, and simulates the REAL Worktree.finish contract
  # (mutates bridge_data, deletes the "worktree" key) by removing the worktree dir from
  # disk when `remove:` is true, never touching real git.
  def spy_finisher(remove: true)
    calls = []
    finisher = lambda do |bridge_data, home:, runner:, merge:|
      calls << { bridge_data: bridge_data, home: home, runner: runner, merge: merge }
      code = bridge_data.dig("worktree", "code")
      FileUtils.rm_rf(code) if remove && code
      bridge_data.delete("worktree")
      bridge_data
    end
    [finisher, calls]
  end

  def run_exec_worktree(disposition:, id: "213", store: @store, home: @home, session: @session,
                        env_session: nil, **seams)
    ExecWorktree.run(store: store, id: id, home: home, disposition: disposition,
                     session: session, env_session: env_session, **seams)
  end

  # --- 1: --disposition routes merge: true|false to the finisher seam --------------

  def test_delivered_calls_finisher_with_merge_true
    build_intent_dir(how_complete: true)
    code = worktree_code_path
    FileUtils.mkdir_p(code)
    finisher, calls = spy_finisher

    result = run_exec_worktree(disposition: "delivered", finisher: finisher,
                               status_checker: clean_status_checker, runner: merged_runner)
    assert_equal 0, result[:exit_code]
    assert_equal 1, calls.length
    assert_equal true, calls.first[:merge]
    assert_match(%r{merge:\s+merged into main}, result[:stdout].join("\n"))
  end

  def test_abandoned_calls_finisher_with_merge_false
    build_intent_dir
    code = worktree_code_path
    FileUtils.mkdir_p(code)
    finisher, calls = spy_finisher

    result = run_exec_worktree(disposition: "abandoned", finisher: finisher,
                               status_checker: unreachable_status_checker)
    assert_equal 0, result[:exit_code]
    assert_equal 1, calls.length
    assert_equal false, calls.first[:merge]
  end

  # --- 6: dirty worktree on delivered refuses ----------------------------------------

  def test_dirty_worktree_on_delivered_exits_3_finisher_never_called
    build_intent_dir
    code = worktree_code_path
    FileUtils.mkdir_p(code)
    finisher, calls = spy_finisher

    result = run_exec_worktree(disposition: "delivered", finisher: finisher,
                               status_checker: dirty_status_checker)
    assert_equal 3, result[:exit_code]
    assert_empty calls
    assert_match(/uncommitted changes/, result[:stderr].join)
  end

  # --- 7: git status failing/raising fails CLOSED ------------------------------------

  def test_status_check_failure_fails_closed_on_delivered
    build_intent_dir
    code = worktree_code_path
    FileUtils.mkdir_p(code)
    finisher, calls = spy_finisher

    result = run_exec_worktree(disposition: "delivered", finisher: finisher,
                               status_checker: raising_status_checker)
    assert_equal 3, result[:exit_code]
    assert_empty calls, "an unproven worktree must refuse: removal force-removes on failure"
    assert_match(/could not inspect/, result[:stderr].join)
  end

  # --- 7b: BLOCKING 1/2 regression: a conflicted merge must not report success ------
  #
  # Worktree.finish is fail-open: on a merge conflict Worktree.merge_branch aborts, warns,
  # and returns false, but Worktree.finish still removes the worktree afterward regardless
  # (scripts/lib/worktree.rb:225-258). Before this fix, exec-worktree discarded that
  # return value and reported success (exit 0, "merged into <branch>") anyway, once the
  # worktree was simply gone. Now it verifies from committed git state and refuses.

  def test_delivered_merge_that_did_not_land_exits_3_and_names_the_branch
    build_intent_dir(how_complete: true)
    code = worktree_code_path
    FileUtils.mkdir_p(code)
    # spy_finisher simulates the real fail-open finisher exactly: it removes the
    # worktree from disk regardless of whether the merge landed.
    finisher, calls = spy_finisher

    result = run_exec_worktree(disposition: "delivered", finisher: finisher,
                               status_checker: clean_status_checker, runner: unmerged_runner)
    assert_equal 3, result[:exit_code]
    assert_equal 1, calls.length, "finish still runs; only the post-finish verdict changes"
    refute_match(/merge:\s+merged into/, result[:stdout].join("\n"))
    assert_match(%r{plastic/213--demo}, result[:stderr].join)
    assert_match(/did not land/, result[:stderr].join)
    assert_match(/was not merged/, result[:stderr].join)
    assert_match(/nothing is lost/, result[:stderr].join)
  end

  # --- 7c: BLOCKING 2 regression: a landed merge names the real integration target, not
  # the source branch, and only after the outcome was actually read -------------------

  def test_delivered_merge_that_landed_exits_0_and_reports_the_real_target_branch
    build_intent_dir(how_complete: true)
    code = worktree_code_path
    FileUtils.mkdir_p(code)
    finisher, calls = spy_finisher

    result = run_exec_worktree(disposition: "delivered", finisher: finisher,
                               status_checker: clean_status_checker,
                               runner: merged_runner(current_branch: "main"))
    assert_equal 0, result[:exit_code]
    assert_equal 1, calls.length
    output = result[:stdout].join("\n")
    assert_match(%r{merge:\s+merged into main}, output)
    refute_match(%r{merge:\s+merged into plastic/213--demo}, output)
  end

  # --- 8: dirty worktree on abandoned proceeds ---------------------------------------

  def test_dirty_worktree_on_abandoned_proceeds
    build_intent_dir
    code = worktree_code_path
    FileUtils.mkdir_p(code)
    finisher, calls = spy_finisher

    result = run_exec_worktree(disposition: "abandoned", finisher: finisher,
                               status_checker: unreachable_status_checker)
    assert_equal 0, result[:exit_code]
    assert_equal 1, calls.length
    assert_equal false, calls.first[:merge]
  end

  # --- 9: no bridge resolves ----------------------------------------------------------

  def test_never_provisioned_project_intent_exits_0_finisher_never_called
    build_intent_dir
    finisher, calls = spy_finisher

    # The derived path exists on nobody's disk: a registered project whose worktree was
    # never created must read as nothing provisioned, not as a dirty worktree (review A5).
    result = run_exec_worktree(disposition: "delivered", session: "nobody-armed-this",
                               finisher: finisher, status_checker: unreachable_status_checker)
    assert_equal 0, result[:exit_code]
    assert_empty calls
    assert_match(/nothing was provisioned/, result[:stdout].join)
  end

  # --- 10: no code worktree recorded ---------------------------------------------------

  def test_no_code_worktree_exits_0_finisher_never_called
    build_intent_dir
    finisher, calls = spy_finisher

    result = run_exec_worktree(disposition: "delivered", finisher: finisher,
                               status_checker: unreachable_status_checker)
    assert_equal 0, result[:exit_code]
    assert_empty calls
    assert_match(/nothing was provisioned/, result[:stdout].join)
  end

  # --- 11: exit 4 when a lock file exists and no session identity resolves -----------

  def test_exit_4_when_lock_present_and_no_session_identity_resolves
    dir = build_intent_dir
    # A blank owner_session (not a foreign one) is what proves NO source resolved: the
    # lock-owner fallback (resolve_session) only counts when owner_session is non-blank.
    File.open(Lock.path(dir), File::WRONLY | File::CREAT | File::EXCL) do |io|
      io.write(JSON.pretty_generate({ "owner_session" => "" }))
    end
    finisher, calls = spy_finisher

    result = run_exec_worktree(disposition: "delivered", session: nil, env_session: nil,
                               finisher: finisher, status_checker: unreachable_status_checker)
    assert_equal 4, result[:exit_code]
    assert_empty calls
  end

  # --- 12: exit 1 for usage/resolution failures ---------------------------------------

  def test_exit_1_for_every_usage_failure
    build_intent_dir
    finisher, calls = spy_finisher

    missing_store = run_exec_worktree(disposition: "delivered", store: nil, finisher: finisher)
    assert_equal 1, missing_store[:exit_code]

    missing_id = run_exec_worktree(disposition: "delivered", id: nil, finisher: finisher)
    assert_equal 1, missing_id[:exit_code]

    missing_home = ExecWorktree.run(store: @store, id: "213", home: nil,
                                    disposition: "delivered", session: @session,
                                    env_session: nil, finisher: finisher)
    assert_equal 1, missing_home[:exit_code]

    missing_disposition = ExecWorktree.run(store: @store, id: "213", home: @home,
                                           disposition: nil, session: @session,
                                           env_session: nil, finisher: finisher)
    assert_equal 1, missing_disposition[:exit_code]

    bad_disposition = run_exec_worktree(disposition: "maybe", finisher: finisher)
    assert_equal 1, bad_disposition[:exit_code]

    no_match = run_exec_worktree(disposition: "delivered", id: "999", finisher: finisher)
    assert_equal 1, no_match[:exit_code]

    FileUtils.mkdir_p(File.join(@store, "213--dup2"))
    ambiguous = run_exec_worktree(disposition: "delivered", finisher: finisher)
    assert_equal 1, ambiguous[:exit_code]

    assert_empty calls
  end

  SCRIPT = File.expand_path("../scripts/exec-worktree", __dir__)

  def run_exec_worktree_subprocess(*args)
    env = { "CLAUDE_CODE_SESSION_ID" => nil, "PLASTIC_TMP" => @bridge_tmp }
    out = IO.popen(env, [RbConfig.ruby, SCRIPT, *args], err: [:child, :out], &:read)
    [out.strip, $?.exitstatus]
  end

  def test_unknown_flag_exits_1_via_the_real_subprocess
    out, status = run_exec_worktree_subprocess("--bogus")
    assert_equal 1, status
    assert_match(/unknown argument/, out)
  end

  # --- 13: --home normalization: <x>/.plastic and <x> both reach Worktree.finish with home: <x>

  def test_home_normalization_accepts_both_spellings
    build_intent_dir(how_complete: true)
    code = worktree_code_path
    FileUtils.mkdir_p(code)
    finisher, calls = spy_finisher

    result = run_exec_worktree(disposition: "delivered", home: @plastic_home,
                               finisher: finisher, status_checker: clean_status_checker,
                               runner: merged_runner)
    assert_equal 0, result[:exit_code]
    assert_equal @home, calls.first[:home]
  end

  def test_home_normalization_accepts_os_home_directly
    build_intent_dir(how_complete: true)
    code = worktree_code_path
    FileUtils.mkdir_p(code)
    finisher, calls = spy_finisher

    result = run_exec_worktree(disposition: "delivered", home: @home,
                               finisher: finisher, status_checker: clean_status_checker,
                               runner: merged_runner)
    assert_equal 0, result[:exit_code]
    assert_equal @home, calls.first[:home]
  end

  # --- 14: guard: never Lock.release, never Lock.takeover, never a test suite ---------

  def test_never_calls_lock_release_lock_takeover_or_a_test_suite
    lib_src = File.read(File.expand_path("../scripts/lib/exec_worktree.rb", __dir__))
    cli_src = File.read(File.expand_path("../scripts/exec-worktree", __dir__))
    combined = lib_src + cli_src

    refute_match(/Lock\.release\b/, combined,
                 "D6 parks the lock gap with intent 254; exec-worktree must never call Lock.release")
    refute_match(/Lock\.takeover\b/, combined,
                 "D6 parks the lock gap with intent 254; exec-worktree must never call Lock.takeover")
    refute_match(/ruby -Itest/, combined,
                 "D8 keeps suite execution in verify-intent; exec-worktree must never invoke it")
    refute_match(/\brake\b/, combined,
                 "D8 keeps suite execution in verify-intent; exec-worktree must never invoke it")
    refute_match(/\bminitest\b/i, combined,
                 "D8 keeps suite execution in verify-intent; exec-worktree must never invoke it")
  end
end
