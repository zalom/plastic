require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "stringio"
require_relative "../scripts/lib/lock"
require_relative "../scripts/lib/bridge"
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

  def repair(session = "sess-1")
    Bridge.repair_lock(session, intent_id: "96", intent_dir: @intent_dir,
                       store: @store, name: "demo", tmp: @tmp)
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

  def test_repair_is_idempotent_and_rebuilds_both_sides
    2.times do
      report = repair
      assert_equal "repaired", report["status"]
    end
    lock = Lock.read(@intent_dir)
    assert_equal "sess-1", lock["owner_session"]
    bridge = Bridge.read("sess-1", intent_id: "96", tmp: @tmp)
    refute_nil bridge
    assert_equal "96", bridge.dig("intent", "id")
    assert_equal "sess-1", bridge.dig("lock", "owner_session")
    refute bridge["lock"].key?("pid")
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
    report = Bridge.repair_lock("sess-1", intent_id: "96", intent_dir: @intent_dir,
                                store: @store, name: "demo", tmp: @tmp, harness: :codex)
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

  def test_repair_migrates_legacy_tmp_only_pid_lock_state
    # Legacy world: a /tmp bridge with a pid-stamped lock block and NO
    # delivery.lock file (pre-108). Repair builds the durable file from disk
    # truth and rewrites the cache without a pid.
    legacy = {
      "session" => "sess-1",
      "intent" => { "id" => "96", "dir" => "96--demo", "store" => @store,
                    "name" => "demo" },
      "build" => { "stage" => "why", "auto" => false },
      "lock" => { "owner_session" => "sess-1", "pid" => 12345,
                  "acquired_at" => "2026-07-01T00:00:00Z", "host" => "old" },
    }
    Bridge.write("sess-1", legacy, tmp: @tmp)
    report = repair
    assert_equal "repaired", report["status"]
    assert File.exist?(Lock.path(@intent_dir))
    bridge = Bridge.read("sess-1", intent_id: "96", tmp: @tmp)
    refute bridge["lock"].key?("pid"), "migration strips the legacy pid"
  end

  def test_repair_preserves_the_armed_auto_flag
    legacy = {
      "session" => "sess-1",
      "intent" => { "id" => "96", "dir" => "96--demo", "store" => @store,
                    "name" => "demo" },
      "build" => { "stage" => "why", "auto" => true },
    }
    Bridge.write("sess-1", legacy, tmp: @tmp)
    repair
    assert_equal true, Bridge.read("sess-1", intent_id: "96", tmp: @tmp).dig("build", "auto")
  end

  def test_repair_enriches_same_owner_legacy_lock_from_explicit_metadata
    acquired_at = Time.utc(2026, 7, 1, 12, 0, 0)
    Lock.acquire(@intent_dir, session: "sess-1", host: "original-host", now: acquired_at)
    Lock.add_delegate(@intent_dir, delegate: "delegate-1", session: "sess-1",
                      now: acquired_at + 1)
    original = Lock.read(@intent_dir)
    heartbeat_at = acquired_at + 60
    report = Bridge.repair_lock("sess-1", intent_id: "96", intent_dir: @intent_dir,
                                store: @store, name: "demo", tmp: @tmp,
                                harness: :codex, agent: "plastic-enforcer",
                                model: "gpt-5", thread: "thread-96", now: heartbeat_at)
    assert_equal "repaired", report["status"]
    lock = Lock.read(@intent_dir)
    assert_equal "codex", lock["owner_harness"]
    assert_equal "plastic-enforcer", lock["owner_agent"]
    assert_equal "gpt-5", lock["owner_model"]
    assert_equal "thread-96", lock["owner_thread"]
    assert_nil lock["run_mode"], "repair without a bridge or explicit mode must not invent guided"
    assert_equal original["acquired_at"], lock["acquired_at"]
    assert_equal "original-host", lock["host"]
    assert_equal original["delegates"], lock["delegates"]
    assert_equal original["delegate_activity"], lock["delegate_activity"]
    assert_in_delta heartbeat_at.to_f, File.mtime(Lock.path(@intent_dir)).to_f, 0.001
  end

  def test_repair_without_metadata_keeps_identity_unknown_and_does_not_infer_cache
    Lock.acquire(@intent_dir, session: "sess-1")
    legacy = {
      "session" => "sess-1",
      "intent" => { "id" => "96", "dir" => "96--demo", "store" => @store,
                    "name" => "demo" },
      "build" => { "stage" => "why", "auto" => true },
      "lock" => { "owner_session" => "sess-1", "owner_harness" => "codex",
                  "owner_agent" => "cached-agent", "owner_model" => "cached-model",
                  "owner_thread" => "cached-thread" },
    }
    Bridge.write("sess-1", legacy, tmp: @tmp)
    repair
    lock = Lock.read(@intent_dir)
    assert_nil lock["owner_harness"]
    assert_nil lock["owner_agent"]
    assert_nil lock["owner_model"]
    assert_nil lock["owner_thread"]
    assert_equal "auto", lock["run_mode"], "mode derives only from the current bridge auto boolean"
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

  def test_repair_provisions_so_selection_keys_on_the_repaired_intent
    repo = File.join(@home, "repo")
    FileUtils.mkdir_p(repo)
    File.write(File.join(@home, ".plastic", "projects.yml"),
               "projects:\n  demo:\n    path: #{repo}\n")

    code_wt = File.join(repo, ".claude", "worktrees", "96--demo")
    sib_wt  = File.join(repo, ".claude", "worktrees", "97--sib")
    FileUtils.mkdir_p(File.join(code_wt, "scripts"))
    FileUtils.mkdir_p(sib_wt)
    edited = File.join(code_wt, "scripts", "app.rb")

    # Concurrent same-session sibling (97), fully armed, in its own worktree.
    sibling = {
      "session" => "sess-1",
      "intent"  => { "id" => "97", "dir" => "97--sib", "store" => @store, "name" => "sib" },
      "build"   => { "stage" => "how", "auto" => true, "last_activity" => Time.now.utc.iso8601 },
      "worktree" => { "code" => sib_wt, "code_branch" => "plastic/97--sib",
                      "store" => nil, "store_branch" => nil, "provisioned" => true },
      "lock" => { "owner_session" => nil, "acquired_at" => nil, "host" => nil,
                  "type" => nil, "delegates" => [] },
    }
    Bridge.write("sess-1", sibling, tmp: @tmp)

    with_worktree(:provision, ->(d, *_a, **_kw) {
      d["worktree"] = { "code" => code_wt, "code_branch" => "plastic/96--demo",
                         "store" => nil, "store_branch" => nil, "provisioned" => true }
      d
    }) do
      report = repair
      assert_equal "repaired", report["status"]

      after = Bridge.read("sess-1", intent_id: "96", tmp: @tmp)
      assert_equal code_wt, after.dig("worktree", "code"),
                   "AC1: the repaired bridge carries non-nil worktree.code"

      ep = Bridge.discover_bridge(session: "sess-1", cwd: code_wt, tmp: @tmp, edited_path: edited)
      assert_equal "96", ep&.dig("intent", "id"),
                   "AC2: an edited-path write inside 96's worktree resolves to 96, not nil"

      assert_equal 2, Bridge.bridge_cwd_tier(after, code_wt),
                   "AC3: 96 tiers at 2 (worktree.code match) in its own worktree"

      # Make the sibling the mtime winner; tier must still decide over it.
      sib_file = Bridge.path("sess-1", intent_id: "97", tmp: @tmp)
      File.utime(Time.now + 100, Time.now + 100, sib_file)
      cwd_only = Bridge.discover_bridge(session: "sess-1", cwd: code_wt, tmp: @tmp)
      assert_equal "96", cwd_only&.dig("intent", "id"),
                   "AC3: from 96's own worktree cwd resolves to 96, not the newer sibling"
    end
  end

  def test_repair_stamps_the_true_stage_not_why
    File.write(File.join(@intent_dir, "spec.md"), "# Spec\nreal\n")
    report = repair
    assert_equal "repaired", report["status"]
    bridge = Bridge.read("sess-1", intent_id: "96", tmp: @tmp)
    assert_equal "how", bridge.dig("build", "stage"),
                 "AC4: repair stamps the true derived stage, not a hardcoded why"
  end

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

  def test_released_repaired_bridge_removes_its_worktree
    repo = File.join(@home, "repo")
    FileUtils.mkdir_p(repo)
    File.write(File.join(@home, ".plastic", "projects.yml"),
               "projects:\n  demo:\n    path: #{repo}\n")
    code_wt = File.join(repo, ".claude", "worktrees", "96--demo")
    FileUtils.mkdir_p(code_wt)

    after = nil
    with_worktree(:provision, ->(d, *_a, **_kw) {
      d["worktree"] = { "code" => code_wt, "code_branch" => "plastic/96--demo",
                         "store" => nil, "store_branch" => nil, "provisioned" => true }
      d
    }) do
      repair
      after = Bridge.read("sess-1", intent_id: "96", tmp: @tmp)
    end

    recorder = Recorder.new
    Worktree.release(after, home: @home, runner: recorder)
    removes = recorder.calls.select { |c| c.include?("remove") && c.include?(code_wt) }
    refute_empty removes,
                 "AC5: End cleanup issues `worktree remove` for the repaired intent's code worktree"
  end

  # --- CLI verbs ---------------------------------------------------------------

  def test_cli_status_reports_lock_and_bridge
    Lock.acquire(@intent_dir, session: "sess-1")
    out, _err, st = cli("status")
    assert st.success?
    assert_includes out, "sess-1"
    assert_includes out, "delivery"
  end

  def test_cli_who_renders_enriched_lock_claim_and_delegate_without_mutation
    now = Time.at(Time.now.to_i).utc
    Lock.acquire(@intent_dir, session: "sess-a", now: now,
                 harness: "codex", agent: "plastic-enforcer", model: "gpt-5",
                 thread: "thread-a", run_mode: "auto")
    Lock.add_delegate(@intent_dir, delegate: "delegate-1", session: "sess-a", now: now,
                      harness: "codex", agent: "plastic-planner", model: "gpt-5",
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
      Delegate: plastic-planner via Codex, active
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
    assert_includes err, "strictly durable-state only"
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

  def test_cli_fix_without_mode_preserves_known_durable_mode_when_bridge_is_missing
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
                        "--agent", "plastic-planner", "--model", "gpt-5", "--thread", "thread-d")
    assert st.success?, err
    activity = Lock.read(@intent_dir)["delegate_activity"].last
    assert_equal %w[codex plastic-planner gpt-5 thread-d active],
                 activity.values_at("harness", "agent", "model", "thread", "status")

    _out, err, st = cli("delegate", "--delegate", "sub-1", "--status", "finished")
    assert st.success?, err
    assert_equal "finished", Lock.read(@intent_dir)["delegate_activity"].last["status"]
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
