require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require "json"
require "fileutils"
require_relative "../scripts/lib/session_ledger"
require "rbconfig"
require "stringio"
require_relative "../scripts/lib/lock"
require_relative "../scripts/lib/bridge"
require_relative "../scripts/lib/arm"
require_relative "../scripts/lib/worktree"

# The one deterministic repair (intent 108, D5) and its CLI entry point.
# Hermetic: store in mktmpdir; bridges under an injected tmp (kwarg for the
# in-process library calls, PLASTIC_TMP for the CLI child process).
class PlasticLockCliTest < Minitest::Test
  CLI = File.expand_path("../scripts/plastic-lock", __dir__)

  def setup
    @tmp = Dir.mktmpdir("plock-tmp")
    @home = Dir.mktmpdir("plock-home")
    @store = File.join(@home, ".plastic", "projects", "demo", "store")
    @intent_dir = File.join(@store, "96--demo")
    FileUtils.mkdir_p(@intent_dir)
    File.write(File.join(@intent_dir, "96--demo.md"), "## Intent\nDemo\n")
    File.write(File.join(File.dirname(@store), "INDEX.md"),
               "## Active\n- [96 — demo](96--demo/96--demo.md)\n\n## Future\n")

    # Neutralize real worktree git ops by default (intent 136: repair_lock now
    # provisions too) so the in-process repair tests never shell out to real
    # git or write the live ~/.plastic. Dedicated tests below re-stub locally.
    @real_provision = Worktree.method(:provision)
    Worktree.define_singleton_method(:provision) { |d, *_a, **_kw| d }
  end

  def teardown
    FileUtils.rm_rf(@tmp)
    FileUtils.rm_rf(@home)
    Worktree.define_singleton_method(:provision, @real_provision) if @real_provision
  end

  def repair(session = "sess-1", **kw)
    Arm.repair(intent_dir: @intent_dir, session: session, home: @home, **kw)
  end

  # The CLI without --intent-dir: the intent resolves from this session's pointer.
  def cli_bare(*args, session: "sess-1", chdir: @home)
    Open3.capture3({ "PLASTIC_TMP" => @tmp, "CLAUDE_CODE_SESSION_ID" => nil, "HOME" => @home },
                   RbConfig.ruby, CLI, *args, "--session", session, chdir: chdir)
  end

  def cli(*args, session: "sess-1")
    Open3.capture3({ "PLASTIC_TMP" => @tmp, "CLAUDE_CODE_SESSION_ID" => nil, "HOME" => @home },
                   RbConfig.ruby, CLI, *args,
                   "--intent-dir", @intent_dir, "--session", session)
  end

  # Temporarily redefine a Worktree singleton method for one block, restoring it
  # after (mirrors test/bridge_auto_test.rb; Minitest::Mock#stub is unavailable
  # in this bundled minitest).
  def with_worktree(method_name, impl)
    original = Worktree.method(method_name)
    Worktree.define_singleton_method(method_name, impl)
    yield
  ensure
    Worktree.define_singleton_method(method_name, original)
  end

  def capture_stderr
    original = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = original
  end

  # --- repair_lock (library) --------------------------------------------------

  def test_repair_is_idempotent_and_reports_the_stage
    2.times do
      report = repair
      assert_equal "repaired", report["status"]
      assert(report["actions"].any? { |a| a.start_with?("stage ") }, "the report names the stage")
    end
    lock = Lock.read(@intent_dir)
    assert_equal "sess-1", lock["owner_session"]
    refute lock.key?("pid")
  end

  def test_repair_backs_off_from_a_fresh_foreign_lock
    Lock.acquire(@intent_dir, session: "other")
    report = repair
    assert_equal "held", report["status"]
    assert_equal "other", Lock.read(@intent_dir)["owner_session"]
  end

  def test_repair_reports_stale_foreign_and_points_at_reclaim
    Lock.acquire(@intent_dir, session: "other")
    FileUtils.touch(Lock.path(@intent_dir), mtime: Time.now - 4000)
    report = repair
    assert_equal "stale", report["status"]
    assert_includes report["hint"], "reclaim"
  end

  def test_repair_reports_stale_hint_with_dollar_prefix_for_codex_harness
    Lock.acquire(@intent_dir, session: "other")
    FileUtils.touch(Lock.path(@intent_dir), mtime: Time.now - 4000)
    report = repair(harness: :codex)
    assert_equal "stale", report["status"]
    assert_includes report["hint"], "$plastic-doctor reclaim the lock"
    refute_includes report["hint"], "/plastic-doctor"
  end

  def test_repair_removes_a_corrupt_lock_and_rebuilds
    File.write(Lock.path(@intent_dir), "{ nope")
    report = repair
    assert_equal "repaired", report["status"]
    assert_equal "sess-1", Lock.read(@intent_dir)["owner_session"]
  end

  def test_repair_enriches_same_owner_legacy_lock_from_explicit_metadata
    acquired_at = Time.utc(2026, 7, 1, 12, 0, 0)
    Lock.acquire(@intent_dir, session: "sess-1", host: "original-host", now: acquired_at)
    Lock.add_delegate(@intent_dir, delegate: "delegate-1", session: "sess-1",
                      now: acquired_at + 1)
    original = Lock.read(@intent_dir)
    heartbeat_at = acquired_at + 60
    report = repair(harness: :codex, agent: "plastic-enforcer",
                    model: "gpt-5", thread: "thread-96", now: heartbeat_at)
    assert_equal "repaired", report["status"]
    lock = Lock.read(@intent_dir)
    assert_equal "codex", lock["owner_harness"]
    assert_equal "plastic-enforcer", lock["owner_agent"]
    assert_equal "gpt-5", lock["owner_model"]
    assert_equal "thread-96", lock["owner_thread"]
    assert_nil lock["run_mode"], "repair without a mode on disk or in the call must not invent guided"
    assert_equal original["acquired_at"], lock["acquired_at"]
    assert_equal "original-host", lock["host"]
    assert_equal original["delegates"], lock["delegates"]
    assert_equal original["delegate_activity"], lock["delegate_activity"]
    assert_in_delta heartbeat_at.to_f, File.mtime(Lock.path(@intent_dir)).to_f, 0.001
  end

  def test_cli_fix_without_harness_keeps_owner_harness_unknown
    Lock.acquire(@intent_dir, session: "sess-1")
    out, err, st = cli("fix")
    assert st.success?, "#{out}\n#{err}"
    assert_nil Lock.read(@intent_dir)["owner_harness"]
  end

  def test_cli_fix_with_explicit_codex_harness_enriches_owner
    Lock.acquire(@intent_dir, session: "sess-1")
    out, err, st = cli("fix", "--harness", "codex")
    assert st.success?, "#{out}\n#{err}"
    assert_equal "codex", Lock.read(@intent_dir)["owner_harness"]
  end

  # --- intent 136: repair_lock must provision the worktree ---------------------
  # repair_lock rebuilds the bridge via derive but (pre-fix) never calls
  # Worktree.provision, so the rebuilt bridge keeps derive's default
  # worktree.code: nil and wipes any previously complete worktree block.

  def test_repair_provision_failure_still_repairs
    out = capture_stderr do
      with_worktree(:provision, ->(*_a, **_kw) { raise "boom" }) do
        report = repair
        assert_equal "repaired", report["status"], "AC6: a provision raise must not break the repair"
        assert_equal "sess-1", Lock.read(@intent_dir)["owner_session"]
      end
    end
    refute_empty out, "AC6: the provision raise is logged, mirroring arm's survive-raise contract"
  end

  # Fake ShellRunner that records `git worktree remove` calls (proves the
  # wiped block orphans a worktree; an intact block does not).
  class Recorder
    Result = Struct.new(:status, :stdout, :stderr) { def success?; status.zero?; end }
    attr_reader :calls
    def initialize; @calls = []; end
    def run(*args); @calls << args.map(&:to_s); Result.new(0, "", ""); end
  end

  def test_released_repaired_intent_removes_its_worktree
    repo = File.join(@home, "repo")
    FileUtils.mkdir_p(repo)
    File.write(File.join(@home, ".plastic", "projects.yml"),
               "projects:\n  demo:\n    path: #{repo}\n")
    code_wt = File.join(repo, ".claude", "worktrees", "96--demo")
    FileUtils.mkdir_p(code_wt)

    with_worktree(:provision, ->(d, *_a, **_kw) { d }) { repair }
    after = Arm.bridge_hash(intent_dir: @intent_dir, home: @home)
    assert_equal code_wt, after.dig("worktree", "code"), "the block is derived from projects.yml and the directory on disk"

    recorder = Recorder.new
    Worktree.release(after, home: @home, runner: recorder)
    removes = recorder.calls.select { |c| c.include?("remove") && c.include?(code_wt) }
    refute_empty removes,
                 "AC5: End cleanup issues `worktree remove` for the repaired intent's code worktree"
  end

  # --- CLI verbs ---------------------------------------------------------------

  def test_cli_status_reports_lock_worktree_and_pointer
    Lock.acquire(@intent_dir, session: "sess-1")
    out, _err, st = cli("status")
    assert st.success?
    assert_includes out, "sess-1"
    assert_includes out, "delivery"
    report = JSON.parse(out)
    assert report.key?("worktree")
    assert_equal false, report["pointer_names_intent"]
    refute report.key?("bridge_present"), "the bridge cache fields left in 2.0 (intent 307)"
  end

  # --- arm (intent 307) ---------------------------------------------------------

  def test_cli_arm_takes_the_lock_and_points_the_session
    out, err, st = cli("arm", "--mode", "auto", "--agent", "plastic-enforcer", "--harness", "claude")
    assert st.success?, "#{out}\n#{err}"
    lock = Lock.read(@intent_dir)
    assert_equal "sess-1", lock["owner_session"]
    assert_equal "auto", lock["run_mode"]
    assert_equal "plastic-enforcer", lock["owner_agent"]
    pointer = Arm.read_pointer("sess-1", home: @home)
    assert_equal "96", pointer
    report = JSON.parse(out)
    assert_equal "acquired", report["status"]
    assert_equal false, report.dig("worktree", "provisioned"), "no repo is registered, so provisioning fails open"
  end

  def test_cli_arm_exits_1_on_a_held_lock_with_the_doctor_hint
    Lock.acquire(@intent_dir, session: "other")
    _out, err, st = cli("arm")
    refute st.success?
    assert_includes err, "held by session other"
    assert_includes err, "/plastic-doctor"
    assert_equal "other", Lock.read(@intent_dir)["owner_session"]
    assert_nil Arm.read_pointer("sess-1", home: @home)
  end

  def test_cli_arm_needs_an_intent_dir
    _out, err, st = cli_bare("arm")
    refute st.success?
    assert_includes err, "needs --intent-dir"
  end

  def test_cli_release_resets_the_pointer
    cli("arm")
    assert_equal "96", Arm.read_pointer("sess-1", home: @home)
    _out, _err, st = cli("release")
    assert st.success?
    refute File.exist?(Lock.path(@intent_dir))
    assert_equal SessionLedger.day_id, Arm.read_pointer("sess-1", home: @home)
  end

  def test_cli_resolves_the_intent_from_the_pointer_when_no_intent_dir_is_given
    # realpath on both sides: macOS mounts tmp under /var, a symlink to /private/var, and
    # the project match compares expanded paths, not resolved ones.
    FileUtils.mkdir_p(File.join(@home, "repo"))
    repo = File.realpath(File.join(@home, "repo"))
    File.write(File.join(@home, ".plastic", "projects.yml"), "projects:\n  demo:\n    path: #{repo}\n")
    cli("arm")
    out, err, st = cli_bare("status", chdir: repo)
    assert st.success?, "#{out}\n#{err}"
    assert_equal @intent_dir, JSON.parse(out)["intent_dir"]
  end

  def test_cli_reports_no_intent_when_the_pointer_holds_a_day_id
    Arm.write_pointer("sess-1", SessionLedger.day_id, home: @home)
    _out, err, st = cli_bare("status")
    refute st.success?
    assert_includes err, "no intent resolved"
  end

  def test_cli_who_renders_enriched_lock_claim_and_delegate_without_mutation
    now = Time.at(Time.now.to_i).utc
    Lock.acquire(@intent_dir, session: "sess-a", now: now,
                 harness: "codex", agent: "plastic-enforcer", model: "gpt-5",
                 thread: "thread-a", run_mode: "auto")
    Lock.add_delegate(@intent_dir, delegate: "delegate-1", session: "sess-a", now: now,
                      harness: "codex", agent: "plastic-executor", model: "gpt-5",
                      thread: "thread-d")
    Claim.acquire_claim(@intent_dir, "plan.md", session: "sess-a",
                        delegate: "delegate-1", now: now)
    FileUtils.touch(Lock.path(@intent_dir), mtime: now)
    FileUtils.touch(Claim.path(@intent_dir, "plan.md"), mtime: now)
    paths = [Lock.path(@intent_dir), Claim.path(@intent_dir, "plan.md")]
    before = paths.to_h { |path| [path, [File.binread(path), File.stat(path).mtime]] }

    out, err, st = cli("who")

    assert st.success?, err
    assert_equal <<~TEXT, out
      96 · demo
      State: fresh
      Controller: plastic-enforcer via Codex
      Session: sess-a
      Heartbeat: #{now.iso8601}
      Claims: plan.md by delegate-1
      Delegate: plastic-executor via Codex, active
    TEXT
    paths.each do |path|
      assert_equal before[path][0], File.binread(path), "who changed bytes for #{path}"
      assert_equal before[path][1], File.stat(path).mtime, "who changed mtime for #{path}"
    end
  end

  def test_cli_who_renders_legacy_unknowns_without_rewriting
    path = Lock.path(@intent_dir)
    File.write(path, JSON.pretty_generate(
      "type" => "delivery", "owner_session" => "legacy-sess", "host" => "old",
      "acquired_at" => "2026-07-01T00:00:00Z", "delegates" => ["legacy-delegate"]
    ))
    before_bytes = File.binread(path)
    before_mtime = File.stat(path).mtime

    out, err, st = cli("who")

    assert st.success?, err
    assert_includes out, "Controller: Unknown via Unknown"
    assert_includes out, "Session: legacy-sess"
    assert_includes out, "Delegate: Unknown via Unknown, Unknown"
    assert_equal before_bytes, File.binread(path)
    assert_equal before_mtime, File.stat(path).mtime
  end

  def test_cli_who_distinguishes_stale_corrupt_and_missing_locks
    Lock.acquire(@intent_dir, session: "old")
    FileUtils.touch(Lock.path(@intent_dir), mtime: Time.now - Lock::TTL_SECONDS - 10)
    out, = cli("who")
    assert_includes out, "State: stale"

    File.write(Lock.path(@intent_dir), "{ nope")
    out, = cli("who")
    assert_equal "96 · demo\nState: corrupt\nController: Unknown via Unknown\nSession: Unknown\nHeartbeat: none\nClaims: none\nDelegate: none\n", out

    File.delete(Lock.path(@intent_dir))
    out, = cli("who")
    assert_includes out, "State: none"
    assert_includes out, "Heartbeat: none"
  end

  def test_cli_who_requires_explicit_intent_dir_instead_of_reading_bridge
    out, err, st = Open3.capture3({ "PLASTIC_TMP" => @tmp }, RbConfig.ruby, CLI, "who")
    refute st.success?, out
    assert_includes err, "needs --intent-dir"
  end

  def test_cli_fix_is_idempotent
    out1, _e1, st1 = cli("fix")
    out2, _e2, st2 = cli("fix")
    assert st1.success? && st2.success?
    assert File.exist?(Lock.path(@intent_dir))
    assert_includes out1, "repaired"
    assert_includes out2, "repaired"
  end

  def test_cli_fix_exits_nonzero_when_held_elsewhere
    Lock.acquire(@intent_dir, session: "other")
    _out, err, st = cli("fix")
    refute st.success?
    assert_includes err, "held"
  end

  def test_cli_fix_reports_stale_hint_with_dollar_prefix_when_harness_flag_is_codex
    Lock.acquire(@intent_dir, session: "other")
    FileUtils.touch(Lock.path(@intent_dir), mtime: Time.now - 4000)
    _out, err, st = cli("fix", "--harness", "codex")
    refute_equal 0, st.exitstatus
    assert_includes err, "$plastic-doctor reclaim the lock"
    refute_includes err, "/plastic-doctor"
  end

  def test_cli_release_clears_the_lock
    Lock.acquire(@intent_dir, session: "sess-1")
    _out, _err, st = cli("release")
    assert st.success?
    refute File.exist?(Lock.path(@intent_dir))
  end

  def test_cli_reclaim_takes_over_a_stale_lock_with_audit
    Lock.acquire(@intent_dir, session: "other")
    FileUtils.touch(Lock.path(@intent_dir), mtime: Time.now - 4000)
    _out, _err, st = cli("reclaim")
    assert st.success?
    assert_equal "sess-1", Lock.read(@intent_dir)["owner_session"]
    assert_includes File.read(File.join(@intent_dir, "savepoint.md")), "takeover"
  end

  def test_cli_reclaim_refuses_a_fresh_foreign_lock
    Lock.acquire(@intent_dir, session: "other")
    _out, err, st = cli("reclaim")
    refute st.success?
    assert_includes err, "back off"
    assert_equal "other", Lock.read(@intent_dir)["owner_session"]
  end

  def test_cli_fix_accepts_explicit_owner_metadata_and_mode
    Lock.acquire(@intent_dir, session: "sess-1")
    _out, err, st = cli("fix", "--harness", "codex", "--agent", "plastic-enforcer",
                        "--model", "gpt-5", "--thread", "thread-a", "--mode", "auto")
    assert st.success?, err
    lock = Lock.read(@intent_dir)
    assert_equal %w[codex plastic-enforcer gpt-5 thread-a auto],
                 lock.values_at("owner_harness", "owner_agent", "owner_model", "owner_thread", "run_mode")
  end

  def test_cli_fix_without_mode_preserves_the_durable_mode
    Lock.acquire(@intent_dir, session: "sess-1", run_mode: "auto")
    _out, err, st = cli("fix")
    assert st.success?, err
    assert_equal "auto", Lock.read(@intent_dir)["run_mode"]
  end

  def test_cli_reclaim_accepts_explicit_owner_metadata_and_mode
    Lock.acquire(@intent_dir, session: "other")
    FileUtils.touch(Lock.path(@intent_dir), mtime: Time.now - 4000)
    _out, err, st = cli("reclaim", "--harness", "codex", "--agent", "plastic-enforcer",
                        "--model", "gpt-5", "--thread", "thread-a", "--mode", "auto")
    assert st.success?, err
    assert_equal %w[codex plastic-enforcer gpt-5 thread-a auto],
                 Lock.read(@intent_dir).values_at("owner_harness", "owner_agent", "owner_model",
                                                  "owner_thread", "run_mode")
  end

  def test_cli_delegate_registers_a_subagent_session
    Lock.acquire(@intent_dir, session: "sess-1")
    _out, _err, st = cli("delegate", "--delegate", "sub-1")
    assert st.success?
    assert_includes Lock.read(@intent_dir)["delegates"], "sub-1"
  end

  def test_cli_delegate_records_metadata_and_owner_marks_terminal_status
    Lock.acquire(@intent_dir, session: "sess-1")
    _out, err, st = cli("delegate", "--delegate", "sub-1", "--harness", "codex",
                        "--agent", "plastic-executor", "--model", "gpt-5", "--thread", "thread-d")
    assert st.success?, err
    activity = Lock.read(@intent_dir)["delegate_activity"].last
    assert_equal %w[codex plastic-executor gpt-5 thread-d active],
                 activity.values_at("harness", "agent", "model", "thread", "status")

    _out, err, st = cli("delegate", "--delegate", "sub-1", "--status", "finished",
                        "--harness", "codex", "--agent", "plastic-executor",
                        "--model", "gpt-5", "--thread", "thread-d")
    assert st.success?, err
    activity = Lock.read(@intent_dir)["delegate_activity"].last
    assert_equal %w[codex plastic-executor gpt-5 thread-d finished],
                 activity.values_at("harness", "agent", "model", "thread", "status")
    assert_includes Lock.read(@intent_dir)["delegates"], "sub-1"
  end

  def test_cli_who_prints_the_most_recently_registered_delegate
    Lock.acquire(@intent_dir, session: "sess-1", harness: "codex",
                 agent: "plastic-enforcer")
    Lock.add_delegate(@intent_dir, delegate: "sub-1", session: "sess-1",
                      harness: "codex", agent: "first-agent")
    Lock.add_delegate(@intent_dir, delegate: "sub-2", session: "sess-1",
                      harness: "codex", agent: "second-agent")
    Lock.add_delegate(@intent_dir, delegate: "sub-1", session: "sess-1",
                      harness: "codex", agent: "current-agent")

    out, err, st = cli("who")

    assert st.success?, err
    assert_includes out, "Delegate: current-agent via Codex, active"
  end

  def test_cli_who_prefers_current_active_then_latest_terminal_delegate
    t0 = Time.utc(2026, 7, 14, 12, 0, 0)
    Lock.acquire(@intent_dir, session: "sess-1", harness: "codex",
                 agent: "plastic-enforcer", now: t0)
    Lock.add_delegate(@intent_dir, delegate: "sub-1", session: "sess-1",
                      harness: "codex", agent: "first-agent", now: t0 + 1)
    Lock.add_delegate(@intent_dir, delegate: "sub-2", session: "sess-1",
                      harness: "codex", agent: "second-agent", now: t0 + 2)
    Lock.update_delegate_status(@intent_dir, delegate: "sub-2", status: "finished",
                                session: "sess-1", now: t0 + 3)

    out, err, st = cli("who")
    assert st.success?, err
    assert_includes out, "Delegate: first-agent via Codex, active"

    Lock.update_delegate_status(@intent_dir, delegate: "sub-1", status: "failed",
                                session: "sess-1", now: t0 + 4)
    out, err, st = cli("who")
    assert st.success?, err
    assert_includes out, "Delegate: first-agent via Codex, failed"
  end

  def test_cli_delegate_terminal_status_rejects_nonowner_and_invalid_status
    Lock.acquire(@intent_dir, session: "owner")
    Lock.add_delegate(@intent_dir, delegate: "sub-1", session: "owner")
    _out, err, st = cli("delegate", "--delegate", "sub-1", "--status", "failed",
                        session: "intruder")
    refute st.success?
    assert_includes err, "owner"

    _out, _err, st = cli("delegate", "--delegate", "sub-1", "--status", "active",
                         session: "owner")
    refute st.success?
  end

  def test_cli_delegate_refused_for_non_owner
    Lock.acquire(@intent_dir, session: "other")
    _out, err, st = cli("delegate", "--delegate", "sub-1")
    refute st.success?
    assert_includes err, "owner"
  end
end
