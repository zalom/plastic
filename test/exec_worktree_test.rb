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

# exec-worktree (intent 213, group 2): the order precondition then Worktree.finish.
# Hermetic: every fixture lives under Dir.mktmpdir, PLASTIC_TMP isolates the bridge dir,
# and no test creates, merges, or removes a real git worktree (the finisher seam is always
# injected; the two tests that reach the real Bridge.code_gate_decision predicate exercise
# only its file-presence check, never git). See test/worktree_test.rb and
# test/worktree_cleanup_test.rb for the house-style reference this mirrors.
class ExecWorktreeTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("exec-wt-home")
    @plastic_home = File.join(@home, ".plastic")
    FileUtils.mkdir_p(@plastic_home)
    @store = File.join(@plastic_home, "store")
    FileUtils.mkdir_p(@store)
    @repo = File.join(@home, "repo")
    FileUtils.mkdir_p(@repo)

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

  # Writes a bridge file directly (never through Bridge.arm_*, so no lock is acquired and
  # no real Worktree.provision runs). auto: nil omits build.auto entirely (a guided
  # bridge never sets the key on arm_guided-shaped data either way; code_gate_decision
  # treats absence exactly like false).
  def write_bridge(id: "213", slug: "demo", auto:, worktree_code:, session: @session)
    data = {
      "session" => session,
      "intent" => { "id" => id, "dir" => "#{id}--#{slug}", "store" => @store, "name" => slug },
      "build" => { "auto" => auto },
      "worktree" => worktree_code ? {
        "code" => worktree_code, "code_branch" => "plastic/#{id}--#{slug}", "provisioned" => true,
      } : { "code" => nil, "code_branch" => nil, "provisioned" => false },
      "lock" => {},
    }
    Bridge.write(session, data)
    data
  end

  class FakeStatus
    def initialize(ok)
      @ok = ok
    end

    def success?
      @ok
    end
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

  def unreachable_gate
    lambda do |*_args|
      flunk "gate seam must not be called for an abandoned disposition"
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
    write_bridge(auto: true, worktree_code: code)
    finisher, calls = spy_finisher

    result = run_exec_worktree(disposition: "delivered", finisher: finisher,
                               status_checker: clean_status_checker)
    assert_equal 0, result[:exit_code]
    assert_equal 1, calls.length
    assert_equal true, calls.first[:merge]
  end

  def test_abandoned_calls_finisher_with_merge_false
    build_intent_dir
    code = worktree_code_path
    FileUtils.mkdir_p(code)
    write_bridge(auto: true, worktree_code: code)
    finisher, calls = spy_finisher

    result = run_exec_worktree(disposition: "abandoned", finisher: finisher,
                               status_checker: unreachable_status_checker,
                               gate: unreachable_gate)
    assert_equal 0, result[:exit_code]
    assert_equal 1, calls.length
    assert_equal false, calls.first[:merge]
  end

  # --- 2: the order precondition blocks an AUTO bridge that has not reached How ------

  def test_precondition_blocks_when_plan_missing
    dir = build_intent_dir
    File.write(File.join(dir, "checklist.md"), "# Checklist\nreal\n")
    File.write(File.join(dir, "actions", "ACTION_1.md"), "# Action 1\nreal\n")
    code = worktree_code_path
    FileUtils.mkdir_p(code)
    write_bridge(auto: true, worktree_code: code)
    finisher, calls = spy_finisher

    result = run_exec_worktree(disposition: "delivered", finisher: finisher,
                               status_checker: unreachable_status_checker)
    assert_equal 2, result[:exit_code]
    assert_empty calls
    assert_match(/has not reached How/, result[:stderr].join)
  end

  def test_precondition_blocks_when_checklist_missing
    dir = build_intent_dir
    File.write(File.join(dir, "plan.md"), "# Plan\nreal\n")
    File.write(File.join(dir, "actions", "ACTION_1.md"), "# Action 1\nreal\n")
    code = worktree_code_path
    FileUtils.mkdir_p(code)
    write_bridge(auto: true, worktree_code: code)
    finisher, calls = spy_finisher

    result = run_exec_worktree(disposition: "delivered", finisher: finisher,
                               status_checker: unreachable_status_checker)
    assert_equal 2, result[:exit_code]
    assert_empty calls
  end

  # The intent-133a case: actions/ holds ONLY a .gitkeep, never a real action file.
  def test_precondition_blocks_when_actions_is_gitkeep_only
    dir = build_intent_dir
    File.write(File.join(dir, "plan.md"), "# Plan\nreal\n")
    File.write(File.join(dir, "checklist.md"), "# Checklist\nreal\n")
    File.write(File.join(dir, "actions", ".gitkeep"), "")
    code = worktree_code_path
    FileUtils.mkdir_p(code)
    write_bridge(auto: true, worktree_code: code)
    finisher, calls = spy_finisher

    result = run_exec_worktree(disposition: "delivered", finisher: finisher,
                               status_checker: unreachable_status_checker)
    assert_equal 2, result[:exit_code]
    assert_empty calls
    assert_match(/has not reached How/, result[:stderr].join)
  end

  # --- 3: the order precondition passes when an AUTO bridge HAS reached How ---------

  def test_precondition_passes_on_auto_bridge_that_reached_how
    build_intent_dir(how_complete: true)
    code = worktree_code_path
    FileUtils.mkdir_p(code)
    write_bridge(auto: true, worktree_code: code)
    finisher, calls = spy_finisher

    result = run_exec_worktree(disposition: "delivered", finisher: finisher,
                               status_checker: clean_status_checker)
    assert_equal 0, result[:exit_code]
    assert_equal 1, calls.length
    assert_match(/precondition: passed/, result[:stdout].join("\n"))
  end

  # --- 4: on a GUIDED bridge the precondition is advisory only, never the gate -------

  def test_guided_bridge_precondition_is_advisory_not_the_enforcement_point
    build_intent_dir # How deliberately NOT reached; a guided bridge must still proceed
    code = worktree_code_path
    FileUtils.mkdir_p(code)
    write_bridge(auto: false, worktree_code: code)
    finisher, calls = spy_finisher

    result = run_exec_worktree(disposition: "delivered", finisher: finisher,
                               status_checker: clean_status_checker)
    assert_equal 0, result[:exit_code]
    assert_equal 1, calls.length
    output = result[:stdout].join("\n")
    assert_match(/precondition: advisory \(guided bridge\)/, output)
    assert_match(/not the enforcement point/, output)
    assert_match(/advisory only/, output)
  end

  # --- 5: abandoned NEVER runs the precondition --------------------------------------

  def test_abandoned_never_calls_the_gate_seam
    build_intent_dir # How not reached; irrelevant for abandoned
    code = worktree_code_path
    FileUtils.mkdir_p(code)
    write_bridge(auto: true, worktree_code: code)
    finisher, calls = spy_finisher

    result = run_exec_worktree(disposition: "abandoned", finisher: finisher,
                               gate: unreachable_gate, status_checker: unreachable_status_checker)
    assert_equal 0, result[:exit_code]
    assert_equal 1, calls.length
    assert_equal false, calls.first[:merge]
  end

  # --- 6: dirty worktree on delivered refuses ----------------------------------------

  def test_dirty_worktree_on_delivered_exits_3_finisher_never_called
    build_intent_dir
    code = worktree_code_path
    FileUtils.mkdir_p(code)
    write_bridge(auto: false, worktree_code: code) # guided: precondition is advisory-nil
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
    write_bridge(auto: false, worktree_code: code)
    finisher, calls = spy_finisher

    result = run_exec_worktree(disposition: "delivered", finisher: finisher,
                               status_checker: raising_status_checker)
    assert_equal 3, result[:exit_code]
    assert_empty calls, "an unproven worktree must refuse: removal force-removes on failure"
    assert_match(/could not inspect/, result[:stderr].join)
  end

  # --- 8: dirty worktree on abandoned proceeds ---------------------------------------

  def test_dirty_worktree_on_abandoned_proceeds
    build_intent_dir
    code = worktree_code_path
    FileUtils.mkdir_p(code)
    write_bridge(auto: true, worktree_code: code)
    finisher, calls = spy_finisher

    result = run_exec_worktree(disposition: "abandoned", finisher: finisher,
                               status_checker: unreachable_status_checker,
                               gate: unreachable_gate)
    assert_equal 0, result[:exit_code]
    assert_equal 1, calls.length
    assert_equal false, calls.first[:merge]
  end

  # --- 9: no bridge resolves ----------------------------------------------------------

  def test_no_bridge_resolves_exits_0_loudly_finisher_never_called
    build_intent_dir
    finisher, calls = spy_finisher

    result = run_exec_worktree(disposition: "delivered", session: "nobody-armed-this",
                               finisher: finisher, status_checker: unreachable_status_checker,
                               gate: unreachable_gate)
    assert_equal 0, result[:exit_code]
    assert_empty calls
    assert_match(/no bridge resolved/, result[:stdout].join)
    assert_match(/orphan/, result[:stdout].join)
  end

  # --- 10: no code worktree recorded ---------------------------------------------------

  def test_no_code_worktree_exits_0_precondition_skipped_finisher_never_called
    build_intent_dir
    write_bridge(auto: true, worktree_code: nil)
    finisher, calls = spy_finisher

    result = run_exec_worktree(disposition: "delivered", finisher: finisher,
                               status_checker: unreachable_status_checker,
                               gate: unreachable_gate)
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
                               finisher: finisher, status_checker: unreachable_status_checker,
                               gate: unreachable_gate)
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
    write_bridge(auto: true, worktree_code: code)
    finisher, calls = spy_finisher

    result = run_exec_worktree(disposition: "delivered", home: @plastic_home,
                               finisher: finisher, status_checker: clean_status_checker)
    assert_equal 0, result[:exit_code]
    assert_equal @home, calls.first[:home]
  end

  def test_home_normalization_accepts_os_home_directly
    build_intent_dir(how_complete: true)
    code = worktree_code_path
    FileUtils.mkdir_p(code)
    write_bridge(auto: true, worktree_code: code)
    finisher, calls = spy_finisher

    result = run_exec_worktree(disposition: "delivered", home: @home,
                               finisher: finisher, status_checker: clean_status_checker)
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
