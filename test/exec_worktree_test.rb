# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require_relative "../scripts/lib/exec_worktree"
require_relative "../scripts/lib/lock"

# exec-worktree (intent 213, group 2; intent 390 removed the git it used to run). Plastic
# runs no version control command: this module never inspects, merges, or removes the code
# worktree an intent's delivery derived. Hermetic: every fixture lives under Dir.mktmpdir,
# PLASTIC_TMP isolates the bridge dir, and no test builds or inspects a real git repository.
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

  def run_exec_worktree(disposition:, id: "213", store: @store, home: @home, session: @session,
                        env_session: nil)
    ExecWorktree.run(store: store, id: id, home: home, disposition: disposition,
                     session: session, env_session: env_session)
  end

  # --- the printed report -------------------------------------------------------------

  def test_delivered_report_names_commit_merge_and_worktree_remove
    build_intent_dir(how_complete: true)
    code = worktree_code_path
    FileUtils.mkdir_p(code)

    result = run_exec_worktree(disposition: "delivered")
    assert_equal 0, result[:exit_code]
    out = result[:stdout].join("\n")
    assert_match(/next: commit any remaining changes in #{Regexp.escape(code)}/, out)
    assert_match(%r{git -C #{Regexp.escape(@repo)} merge plastic/213--demo}, out)
    assert_match(%r{git -C #{Regexp.escape(@repo)} worktree remove #{Regexp.escape(code)}}, out)
  end

  def test_abandoned_report_names_no_merge_only_worktree_remove
    build_intent_dir
    code = worktree_code_path
    FileUtils.mkdir_p(code)

    result = run_exec_worktree(disposition: "abandoned")
    assert_equal 0, result[:exit_code]
    out = result[:stdout].join("\n")
    refute_match(/git .* merge/, out)
    assert_match(%r{git -C #{Regexp.escape(@repo)} worktree remove #{Regexp.escape(code)}}, out)
  end

  # --- no worktree resolves ------------------------------------------------------------

  def test_never_provisioned_project_intent_exits_0_and_names_nothing_provisioned
    build_intent_dir

    # The derived path exists on nobody's disk: a registered project whose worktree was
    # never created must read as nothing provisioned.
    result = run_exec_worktree(disposition: "delivered", session: "nobody-armed-this")
    assert_equal 0, result[:exit_code]
    assert_match(/nothing was provisioned/, result[:stdout].join)
  end

  def test_no_code_worktree_exits_0_and_names_nothing_provisioned
    build_intent_dir

    result = run_exec_worktree(disposition: "delivered")
    assert_equal 0, result[:exit_code]
    assert_match(/nothing was provisioned/, result[:stdout].join)
  end

  # --- exit 4 when a lock file exists and no session identity resolves -----------------

  def test_exit_4_when_lock_present_and_no_session_identity_resolves
    dir = build_intent_dir
    # A blank owner_session (not a foreign one) is what proves NO source resolved: the
    # lock-owner fallback (resolve_session) only counts when owner_session is non-blank.
    File.open(Lock.path(dir), File::WRONLY | File::CREAT | File::EXCL) do |io|
      io.write(JSON.pretty_generate({ "owner_session" => "" }))
    end

    result = run_exec_worktree(disposition: "delivered", session: nil, env_session: nil)
    assert_equal 4, result[:exit_code]
  end

  # --- exit 1 for usage/resolution failures ---------------------------------------------

  def test_exit_1_for_every_usage_failure
    build_intent_dir

    missing_store = run_exec_worktree(disposition: "delivered", store: nil)
    assert_equal 1, missing_store[:exit_code]

    missing_id = run_exec_worktree(disposition: "delivered", id: nil)
    assert_equal 1, missing_id[:exit_code]

    missing_home = ExecWorktree.run(store: @store, id: "213", home: nil,
                                    disposition: "delivered", session: @session,
                                    env_session: nil)
    assert_equal 1, missing_home[:exit_code]

    missing_disposition = ExecWorktree.run(store: @store, id: "213", home: @home,
                                           disposition: nil, session: @session,
                                           env_session: nil)
    assert_equal 1, missing_disposition[:exit_code]

    bad_disposition = run_exec_worktree(disposition: "maybe")
    assert_equal 1, bad_disposition[:exit_code]

    no_match = run_exec_worktree(disposition: "delivered", id: "999")
    assert_equal 1, no_match[:exit_code]

    FileUtils.mkdir_p(File.join(@store, "213--dup2"))
    ambiguous = run_exec_worktree(disposition: "delivered")
    assert_equal 1, ambiguous[:exit_code]
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

  # --- --home normalization: <x>/.plastic and <x> both resolve the same repo ----------

  def test_home_normalization_accepts_both_spellings
    build_intent_dir(how_complete: true)
    code = worktree_code_path
    FileUtils.mkdir_p(code)

    result = run_exec_worktree(disposition: "delivered", home: @plastic_home)
    assert_equal 0, result[:exit_code]
    assert_match(%r{git -C #{Regexp.escape(@repo)} worktree remove}, result[:stdout].join)
  end

  def test_home_normalization_accepts_os_home_directly
    build_intent_dir(how_complete: true)
    code = worktree_code_path
    FileUtils.mkdir_p(code)

    result = run_exec_worktree(disposition: "delivered", home: @home)
    assert_equal 0, result[:exit_code]
    assert_match(%r{git -C #{Regexp.escape(@repo)} worktree remove}, result[:stdout].join)
  end

  # --- guard: never runs git, never touches the lock, never runs a test suite ---------

  def test_never_calls_lock_release_lock_takeover_git_or_a_test_suite
    lib_src = File.read(File.expand_path("../scripts/lib/exec_worktree.rb", __dir__))
    cli_src = File.read(File.expand_path("../scripts/exec-worktree", __dir__))
    combined = lib_src + cli_src

    refute_match(/Lock\.release\b/, combined,
                 "D6 parks the lock gap with intent 254; exec-worktree must never call Lock.release")
    refute_match(/Lock\.takeover\b/, combined,
                 "D6 parks the lock gap with intent 254; exec-worktree must never call Lock.takeover")
    refute_match(/system\(|`git|Open3\.|IO\.popen/, combined,
                 "intent 390: Plastic runs no version control command; exec-worktree must never shell out")
    refute_match(/ruby -Itest/, combined,
                 "D8 keeps suite execution in verify-intent; exec-worktree must never invoke it")
    refute_match(/\brake\b/, combined,
                 "D8 keeps suite execution in verify-intent; exec-worktree must never invoke it")
    refute_match(/\bminitest\b/i, combined,
                 "D8 keeps suite execution in verify-intent; exec-worktree must never invoke it")
  end
end
