# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "yaml"
require_relative "../scripts/lib/arm"
require_relative "../scripts/lib/lock"
require_relative "../scripts/lib/worktree"
require_relative "../scripts/lib/session_ledger"

# Arm (intent 307): taking an intent is the lock, the worktree, and the
# session pointer; giving it back reverses all three. Hermetic: a tmp HOME
# holds the sandbox `.plastic` (projects.yml, a project store, the global
# store's `.tmp/`), every git call goes through a fake runner that creates the
# worktree directory on `worktree add` and removes it on `worktree remove`,
# the clock is injected, and CLAUDE_CODE_SESSION_ID is never read (Arm reads
# no environment; `env:` is an argument). Nothing touches the live ~/.plastic.
class ArmTest < Minitest::Test
  class FakeRunner
    attr_reader :calls

    def initialize(&block)
      @calls = []
      @responder = block
    end

    def run(*args)
      a = args.map(&:to_s)
      @calls << a
      if a[0] == "-C" && a[2] == "worktree" && a[3] == "add"
        FileUtils.mkdir_p(a[4])
      elsif a[0] == "-C" && a[2] == "worktree" && a[3] == "remove"
        FileUtils.rm_rf(a[4])
      elsif a[0] == "-C" && a[2] == "rev-parse"
        return Worktree::ShellRunner::Result.new(0, "true\n", "")
      end
      r = @responder ? @responder.call(a) : nil
      r || Worktree::ShellRunner::Result.new(0, "", "")
    end
  end

  def setup
    @home = Dir.mktmpdir("arm-home")
    @plastic = File.join(@home, ".plastic")
    @store = File.join(@plastic, "projects", "demo", "store")
    @global = File.join(@plastic, "store")
    FileUtils.mkdir_p(@store)
    FileUtils.mkdir_p(@global)
    @repo = File.join(@home, "apps", "demo")
    FileUtils.mkdir_p(File.join(@repo, ".git"))
    File.write(File.join(@plastic, "projects.yml"),
               { "projects" => { "demo" => { "path" => @repo } } }.to_yaml)
    @dir = File.join(@store, "96--demo")
    FileUtils.mkdir_p(@dir)
    File.write(File.join(@dir, "96--demo.md"), "## Intent\nDemo\n")
    # The lock lease is judged by file mtime against `now`, so the injected
    # clock must be the real one; freshness tests push the mtime back instead.
    @now = Time.now
    @runner = FakeRunner.new
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def arm(session = "sess-a", **kw)
    Arm.arm(intent_dir: @dir, session: session, home: @home, now: @now, runner: @runner, **kw)
  end

  def pointer(session = "sess-a")
    Arm.read_pointer(session, home: @home)
  end

  def worktree_path
    File.join(@repo, ".claude", "worktrees", "96--demo")
  end

  # --- arm ---------------------------------------------------------------------

  def test_arm_acquires_the_lock_with_run_mode_and_provenance
    result = arm(mode: "auto", harness: "claude", agent: "plastic-enforcer", thread: nil)
    assert_equal :acquired, result[:status]
    lock = Lock.read(@dir)
    assert_equal "sess-a", lock["owner_session"]
    assert_equal "auto", lock["run_mode"]
    assert_equal "claude", lock["owner_harness"]
    assert_equal "plastic-enforcer", lock["owner_agent"]
  end

  def test_arm_stamps_guided_mode_when_asked
    arm(mode: "guided")
    assert_equal "guided", Lock.read(@dir)["run_mode"]
  end

  def test_arm_writes_the_intent_id_into_the_session_pointer
    arm
    assert_equal "96", pointer
    assert File.exist?(File.join(@global, ".tmp", ".gitignore")), "the tmp root stays git-ignored"
  end

  def test_arm_provisions_the_code_worktree_and_reports_it
    result = arm
    assert Dir.exist?(worktree_path)
    assert_equal worktree_path, result[:worktree]["code"]
    assert_equal "plastic/96--demo", result[:worktree]["code_branch"]
    assert_equal true, result[:worktree]["provisioned"]
    add = @runner.calls.find { |c| c[2] == "worktree" && c[3] == "add" }
    refute_nil add
    assert_equal @repo, add[1]
  end

  def test_arm_fails_open_on_an_intent_with_no_repo
    global_dir = File.join(@global, "7--idea")
    FileUtils.mkdir_p(global_dir)
    result = nil
    capture_io do
      result = Arm.arm(intent_dir: global_dir, session: "sess-a", home: @home, now: @now, runner: @runner)
    end
    assert_equal :acquired, result[:status]
    assert_equal false, result[:worktree]["provisioned"]
    assert_nil result[:worktree]["code"]
    assert File.exist?(Lock.path(global_dir)), "the lock is taken even when no worktree can be"
  end

  def test_arm_is_idempotent_for_the_owner
    arm
    result = arm
    assert_equal :owned, result[:status]
    assert_equal "96", pointer
  end

  def test_arm_backs_off_from_a_held_lock_and_touches_nothing
    Lock.acquire(@dir, session: "sess-b", now: @now)
    before = File.read(Lock.path(@dir))
    result = arm
    assert_equal :held, result[:status]
    assert_equal "sess-b", result[:lock]["owner_session"]
    assert_equal before, File.read(Lock.path(@dir))
    assert_nil pointer, "a refused arm never points the session at the intent"
    refute Dir.exist?(worktree_path)
  end

  def test_arm_reports_a_stale_foreign_lock_without_taking_it
    Lock.acquire(@dir, session: "sess-b", now: @now - 4000)
    FileUtils.touch(Lock.path(@dir), mtime: @now - 4000)
    result = Arm.arm(intent_dir: @dir, session: "sess-a", home: @home, now: @now, runner: @runner)
    assert_equal :stale, result[:status]
    assert_equal "sess-b", Lock.read(@dir)["owner_session"]
  end

  def test_arm_reports_a_corrupt_lock
    File.write(Lock.path(@dir), "{ nope")
    result = arm
    assert_equal :corrupt, result[:status]
    assert_equal "{ nope", File.read(Lock.path(@dir))
  end

  def test_arm_with_no_session_uses_the_derived_key
    derived = Arm.derive_key(@store, "96")
    result = Arm.arm(intent_dir: @dir, session: nil, home: @home, now: @now, runner: @runner)
    assert_equal :acquired, result[:status]
    assert_equal derived, Lock.read(@dir)["owner_session"]
    assert_equal derived, result[:session]
  end

  def test_resolve_session_order_is_explicit_then_env_then_derived
    assert_equal "x", Arm.resolve_session("x", env: "e", store: @store, intent_id: "96")
    assert_equal "e", Arm.resolve_session(" ", env: "e", store: @store, intent_id: "96")
    assert_equal Arm.derive_key(@store, "96"), Arm.resolve_session(nil, env: nil, store: @store, intent_id: "96")
  end

  def test_arm_rejects_an_unknown_mode
    assert_raises(ArgumentError) { arm(mode: "manual") }
  end

  # --- worktree_block and bridge_hash -------------------------------------------

  def test_worktree_block_matches_worktree_paths_and_follows_the_directory
    block = Arm.worktree_block(intent_dir: @dir, home: @home)
    assert_equal false, block["provisioned"]
    assert_nil block["code"]
    arm
    block = Arm.worktree_block(intent_dir: @dir, home: @home)
    p = Worktree.paths(slug: "demo", intent_id: "96", intent_slug: "demo", home: @home)
    assert_equal p["code"], block["code"]
    assert_equal p["code_branch"], block["code_branch"]
    assert_equal true, block["provisioned"]
  end

  def test_bridge_hash_carries_the_intent_store_for_worktree_finish
    data = Arm.bridge_hash(intent_dir: @dir, home: @home)
    assert_equal({ "id" => "96", "dir" => "96--demo", "store" => @store }, data["intent"])
    assert data["worktree"].is_a?(Hash)
  end

  # --- disarm ------------------------------------------------------------------

  def test_disarm_removes_the_worktree_then_releases_the_lock_and_resets_the_pointer
    arm
    status = Arm.disarm(intent_dir: @dir, session: "sess-a", home: @home, runner: @runner, now: @now)
    assert_equal :released, status
    refute File.exist?(Lock.path(@dir))
    refute Dir.exist?(worktree_path)
    assert_equal SessionLedger.day_id(@now), pointer
    remove_at = @runner.calls.index { |c| c[2] == "worktree" && c[3] == "remove" }
    refute_nil remove_at, "the worktree is removed"
  end

  def test_disarm_never_releases_a_foreign_fresh_lock
    Lock.acquire(@dir, session: "sess-b", now: @now)
    Arm.write_pointer("sess-a", "96", home: @home)
    status = Arm.disarm(intent_dir: @dir, session: "sess-a", home: @home, runner: @runner, now: @now)
    assert_equal :released, status,
      "disarm releases as the RECORDED owner: end-intent's pre-flight decides who may close"
    refute File.exist?(Lock.path(@dir))
  end

  def test_disarm_leaves_a_pointer_that_names_another_intent_alone
    arm
    Arm.write_pointer("sess-a", "97", home: @home)
    Arm.disarm(intent_dir: @dir, session: "sess-a", home: @home, runner: @runner, now: @now)
    assert_equal "97", pointer
  end

  def test_disarm_with_no_lock_reports_none_and_still_resets_the_pointer
    Arm.write_pointer("sess-a", "96", home: @home)
    status = Arm.disarm(intent_dir: @dir, session: "sess-a", home: @home, runner: @runner, now: @now)
    assert_equal :none, status
    assert_equal SessionLedger.day_id(@now), pointer
  end

  def test_disarm_without_remove_keeps_the_worktree
    arm
    Arm.disarm(intent_dir: @dir, session: "sess-a", home: @home, runner: @runner, now: @now, remove: false)
    assert Dir.exist?(worktree_path)
    refute File.exist?(Lock.path(@dir))
  end

  # --- repair ------------------------------------------------------------------

  def repair(session = "sess-a", **kw)
    Arm.repair(intent_dir: @dir, session: session, home: @home, now: @now, runner: @runner, **kw)
  end

  def test_repair_acquires_when_no_lock_and_provisions
    report = repair(run_mode: "auto")
    assert_equal "repaired", report["status"]
    assert_includes report["actions"], "lock acquired"
    assert_equal "auto", Lock.read(@dir)["run_mode"]
    assert Dir.exist?(worktree_path)
  end

  def test_repair_removes_a_corrupt_lock_and_rebuilds
    File.write(Lock.path(@dir), "{ nope")
    report = repair
    assert_equal "repaired", report["status"]
    assert_includes report["actions"], "removed corrupt delivery.lock"
    assert_equal "sess-a", Lock.read(@dir)["owner_session"]
  end

  def test_repair_backs_off_from_a_fresh_foreign_lock
    Lock.acquire(@dir, session: "sess-b", now: @now)
    report = repair
    assert_equal "held", report["status"]
    assert_equal "sess-b", report["owner"]
    assert_equal "sess-b", Lock.read(@dir)["owner_session"]
  end

  def test_repair_reports_a_stale_foreign_lock_with_the_reclaim_hint
    Lock.acquire(@dir, session: "sess-b", now: @now - 4000)
    FileUtils.touch(Lock.path(@dir), mtime: @now - 4000)
    report = repair(hint_harness: "codex")
    assert_equal "stale", report["status"]
    assert_includes report["hint"], "$plastic-doctor"
  end

  def test_repair_keeps_and_enriches_an_own_lock_without_inventing_a_mode
    Lock.acquire(@dir, session: "sess-a", now: @now)
    report = repair(harness: "claude", agent: "plastic-enforcer")
    assert_equal "repaired", report["status"]
    assert_includes report["actions"], "lock kept (owner)"
    lock = Lock.read(@dir)
    assert_equal "claude", lock["owner_harness"]
    assert_equal "plastic-enforcer", lock["owner_agent"]
    assert_nil lock["run_mode"], "repair without a mode on disk or in the call must not invent one"
  end

  def test_repair_preserves_the_run_mode_already_on_disk
    Lock.acquire(@dir, session: "sess-a", now: @now, run_mode: "auto")
    repair
    assert_equal "auto", Lock.read(@dir)["run_mode"]
  end

  def test_repair_heartbeats_a_delegate_and_keeps_the_owner
    Lock.acquire(@dir, session: "sess-a", now: @now)
    Lock.add_delegate(@dir, delegate: "sub", session: "sess-a")
    report = repair("sub")
    assert_equal "repaired", report["status"]
    assert_includes report["actions"], "lock kept (delegate)"
    assert_equal "sess-a", Lock.read(@dir)["owner_session"]
  end

  # --- the pointer as a resolver -------------------------------------------------

  def test_intent_dir_from_pointer_resolves_an_intent_id_and_ignores_a_day_id
    Arm.write_pointer("sess-a", "96", home: @home)
    assert_equal @dir, Arm.intent_dir_from_pointer("sess-a", home: @home, stores: [@store, @global])
    Arm.write_pointer("sess-a", "20260830", home: @home)
    assert_nil Arm.intent_dir_from_pointer("sess-a", home: @home, stores: [@store, @global])
    assert_nil Arm.intent_dir_from_pointer("nobody", home: @home, stores: [@store])
  end

  # --- owner rule 2026-08-31 (day-ledger direct item): no inline delivery ----
  # A session that already carries a top-level session pointer is a
  # conversation session (SessionStart wrote the pointer at boot); arming an
  # intent there is inline delivery and is refused. A dispatched or headless
  # session has no pre-existing pointer and arms freely. --allow-inline is the
  # explicit owner override.

  def test_arm_refuses_a_session_with_a_preexisting_pointer
    Arm.write_pointer("sess-a", "day-ledger", home: @home)
    result = Arm.arm(intent_dir: @dir, session: "sess-a", home: @home, runner: FakeRunner.new)
    assert_equal :inline_refused, result[:status]
    refute File.exist?(File.join(@dir, "delivery.lock")),
           "a refused arm must not leave a lock behind"
  end

  def test_arm_allow_inline_overrides_the_refusal
    Arm.write_pointer("sess-a", "day-ledger", home: @home)
    result = Arm.arm(intent_dir: @dir, session: "sess-a", home: @home,
                     runner: FakeRunner.new, allow_inline: true)
    assert_equal :acquired, result[:status]
  end

  def test_arm_without_a_preexisting_pointer_still_acquires
    result = Arm.arm(intent_dir: @dir, session: "dispatched-x", home: @home, runner: FakeRunner.new)
    assert_equal :acquired, result[:status]
  end

end
