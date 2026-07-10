require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require_relative "../scripts/lib/bridge"
require_relative "../scripts/lib/worktree"
require_relative "../scripts/lib/lock"

# The composed lock-mechanism surface, end to end (intent 108, the original
# What). Every test is hermetic: injected PLASTIC_TMP (ambient save/restore),
# mktmpdir stores, injected clocks, FakeRunner for git, and Worktree
# provision/release neutralized except where a test exercises them with a fake.
class LockSystemTest < Minitest::Test
  # A fake ShellRunner (worktree_test.rb pattern): records calls, scripted
  # results, every git call "succeeds" by default.
  class FakeRunner
    attr_reader :calls

    def initialize(&block)
      @calls = []
      @responder = block
    end

    def run(*args)
      @calls << args.map(&:to_s)
      r = @responder ? @responder.call(args.map(&:to_s)) : nil
      r || Worktree::ShellRunner::Result.new(0, "true\n", "")
    end
  end

  def setup
    @tmp = Dir.mktmpdir("locksys-tmp")
    @home = Dir.mktmpdir("locksys-home")
    @prev_tmp = ENV["PLASTIC_TMP"]
    @prev_sid = ENV["CLAUDE_CODE_SESSION_ID"]
    ENV["PLASTIC_TMP"] = @tmp
    ENV["CLAUDE_CODE_SESSION_ID"] = nil
    @store = File.join(@home, ".plastic", "projects", "demo", "store")
    %w[96--demo 97--other].each do |d|
      FileUtils.mkdir_p(File.join(@store, d))
      File.write(File.join(@store, d, "#{d}.md"), "## Intent\nDemo\n")
    end
    write_index_active(%w[96 97])
    @dir96 = File.join(@store, "96--demo")
    @dir97 = File.join(@store, "97--other")

    # projects.yml so the real provision (used with a FakeRunner) resolves the
    # demo repo inside this test home.
    @repo = File.join(@home, "apps", "demo")
    FileUtils.mkdir_p(@repo)
    File.write(File.join(@home, ".plastic", "projects.yml"),
               { "projects" => { "demo" => { "path" => @repo } } }.to_yaml)

    # Neutralize real worktree git ops for arms; tests that exercise the
    # worktree surface swap the real methods back in with a FakeRunner.
    @real_provision = Worktree.method(:provision)
    @real_release = Worktree.method(:release)
    stub_worktree
  end

  def teardown
    ENV["PLASTIC_TMP"] = @prev_tmp
    ENV["CLAUDE_CODE_SESSION_ID"] = @prev_sid
    Worktree.define_singleton_method(:provision, @real_provision) if @real_provision
    Worktree.define_singleton_method(:release, @real_release) if @real_release
    FileUtils.rm_rf(@tmp)
    FileUtils.rm_rf(@home)
  end

  def stub_worktree
    Worktree.define_singleton_method(:provision) { |d, *_a, **_kw| d }
    Worktree.define_singleton_method(:release) { |d, *_a, **_kw| d }
  end

  def with_real_worktree
    Worktree.define_singleton_method(:provision, @real_provision)
    Worktree.define_singleton_method(:release, @real_release)
    yield
  ensure
    stub_worktree
  end

  def write_index_active(ids)
    lines = ["## Active"]
    ids.each { |id| lines << "- [#{id} — demo](#{id}--demo/#{id}--demo.md)" }
    lines << ""
    lines << "## Future"
    File.write(File.join(File.dirname(@store), "INDEX.md"), lines.join("\n") + "\n")
  end

  def arm(session, id: "96", dir: @dir96, auto: false)
    args = { intent_id: id, intent_dir: dir, store: @store, name: "demo" }
    auto ? Bridge.arm_auto(session, **args) : Bridge.arm_guided(session, **args)
  end

  def gate(file, session:)
    Bridge.lock_gate_decision(nil, file, session: session, home: @home)
  end

  def repair(session)
    Bridge.repair_lock(session, intent_id: "96", intent_dir: @dir96,
                       store: @store, name: "demo", tmp: @tmp)
  end

  # --- 1. single owner ---------------------------------------------------------

  def test_single_owner_second_session_refused_owner_idempotent
    arm("a")
    err = assert_raises(Bridge::LockHeldError) { arm("b") }
    assert_includes err.message, "/plastic-doctor"

    data = arm("a") # idempotent re-arm, :owned path
    assert_equal "a", data["lock"]["owner_session"]
    assert_equal "a", Lock.read(@dir96)["owner_session"]
  end

  # --- 2. lease expiry and explicit reclaim ------------------------------------

  def test_lease_expiry_gates_takeover
    arm("a")
    status, _ = Lock.takeover(@dir96, session: "b", ttl: 1800)
    assert_equal :fresh, status, "no takeover while the lease is fresh"

    FileUtils.touch(Lock.path(@dir96), mtime: Time.now - 4000)
    status, data = Lock.takeover(@dir96, session: "b", ttl: 1800)
    assert_equal :taken, status
    assert_equal "b", data["owner_session"]
    audit = File.read(File.join(@dir96, "savepoint.md"))
    assert_includes audit, "takeover: b reclaimed delivery lock from a"
  end

  # --- 3. delegation end to end -------------------------------------------------

  def test_delegate_passes_the_gate_stranger_denied_with_routing
    arm("owner-a")
    assert Lock.add_delegate(@dir96, delegate: "sub", session: "owner-a")
    assert_nil gate("#{@dir96}/plan.md", session: "sub")
    reason = gate("#{@dir96}/plan.md", session: "stranger")
    refute_nil reason
    assert_includes reason, "plastic-lock delegate"
  end

  # --- 4. session resolution: all three fallbacks -------------------------------

  def test_explicit_session_keys_the_bridge
    arm("explicit-sid")
    assert File.exist?(File.join(@tmp, "plastic-explicit-sid--96.json"))
    assert_equal "explicit-sid", Lock.read(@dir96)["owner_session"]
  end

  def test_env_session_keys_the_bridge_when_no_explicit
    ENV["CLAUDE_CODE_SESSION_ID"] = "env-sid"
    arm(nil)
    assert File.exist?(File.join(@tmp, "plastic-env-sid--96.json"))
    assert_equal "env-sid", Lock.read(@dir96)["owner_session"]
  ensure
    ENV["CLAUDE_CODE_SESSION_ID"] = nil
  end

  def test_derived_key_when_both_blank_and_warns
    derived = Bridge.derive_key(@store, "96")
    _out, err = capture_io { arm(nil) }
    assert File.exist?(File.join(@tmp, "plastic-#{derived}--96.json"))
    assert_equal derived, Lock.read(@dir96)["owner_session"]
    assert_match(/derived bridge key/, err)
  end

  # --- 5. concurrent parallel sessions ------------------------------------------

  def test_two_sessions_hold_their_own_intents_cross_denied
    arm("a", id: "96", dir: @dir96)
    arm("b", id: "97", dir: @dir97)

    assert_nil gate("#{@dir96}/plan.md", session: "a")
    assert_nil gate("#{@dir97}/plan.md", session: "b")
    refute_nil gate("#{@dir96}/plan.md", session: "b"), "b must not write into a's intent"
    refute_nil gate("#{@dir97}/plan.md", session: "a"), "a must not write into b's intent"

    assert Worktree.lock_held_by_other?(intent_id: "96", store: @store,
                                        current_session: "b", home: @home)
    refute Worktree.lock_held_by_other?(intent_id: "96", store: @store,
                                        current_session: "a", home: @home)
  end

  # --- 6. worktree provision / enforcement / merge-remove ------------------------

  def provision_bridge_with(runner)
    bridge = { "intent" => { "id" => "96", "dir" => "96--demo",
                             "store" => @store, "name" => "demo" } }
    with_real_worktree { Worktree.provision(bridge, home: @home, runner: runner) }
  end

  def test_provision_enforcement_and_merge_remove
    runner = FakeRunner.new
    bridge = provision_bridge_with(runner)

    wt = bridge["worktree"]
    assert_equal true, wt["provisioned"]
    code_wt = File.join(@repo, ".claude", "worktrees", "96--demo")
    assert_equal code_wt, wt["code"]
    gitignore = File.read(File.join(@home, ".plastic", ".gitignore"))
    assert_includes gitignore.lines.map(&:strip), "*.lock"

    # Enforcement: shared checkout blocked (names the worktree), worktree
    # path allowed, outside-repo path allowed (ACTION-10 contract).
    bridge["session"] = "a"
    shared = Bridge.worktree_gate_decision(bridge, File.join(@repo, "lib", "app.rb"), home: @home)
    refute_nil shared
    assert_includes shared, code_wt
    assert_nil Bridge.worktree_gate_decision(bridge, File.join(code_wt, "lib", "app.rb"), home: @home)
    assert_nil Bridge.worktree_gate_decision(bridge, File.join(@home, "elsewhere", "x.md"), home: @home)

    # Merge-remove: finish(merge: true) merges the code branch, then removes
    # both worktrees and clears the block.
    finish_runner = FakeRunner.new
    result = with_real_worktree do
      Worktree.finish(bridge, home: @home, runner: finish_runner, merge: true)
    end
    merges = finish_runner.calls.select { |c| c.include?("merge") }
    removes = finish_runner.calls.select { |c| c.include?("remove") }
    refute_empty merges, "finish(merge: true) must merge the code branch"
    assert_equal 2, removes.length, "both worktrees are removed"
    assert_nil result["worktree"]
  end

  # --- 7. purge on terminal, with the lock guard ---------------------------------

  def test_purge_terminal_respects_lock_and_current_session
    write_index_active([]) # both intents are terminal now
    seed = lambda do |session, id, dir|
      Bridge.write(session, { "session" => session,
                              "intent" => { "id" => id, "dir" => File.basename(dir),
                                            "store" => @store, "name" => "demo" },
                              "build" => { "auto" => false } }, tmp: @tmp)
      Bridge.path(session, intent_id: id, tmp: @tmp)
    end

    terminal = seed.call("t-sess", "96", @dir96) # terminal, no lock -> purges
    locked = seed.call("l-sess", "97", @dir97)   # terminal, lock held -> kept
    current = seed.call("current", "96", @dir96)
    Lock.acquire(@dir97, session: "l-sess")

    removed = Bridge.purge_done_bridges(session: "current", tmp: @tmp)
    assert_includes removed, terminal, "a terminal intent's bridge purges"
    refute File.exist?(terminal)
    assert File.exist?(current), "the current session's bridge never purges"
    refute_includes removed, locked
    assert File.exist?(locked), "a held delivery.lock blocks the purge (D6)"
  end

  # --- 8. per-gate deny/allow matrix ----------------------------------------------

  def test_gate_matrix_denials_name_the_resolving_command
    project_file = File.join(@home, "apps", "demo", "app.rb")

    # code-gate: auto armed, pre-How -> deny naming the plan skills; post-How -> allow.
    auto_bridge = arm("a", auto: true)
    pre = Bridge.code_gate_decision(auto_bridge, project_file, home: @home)
    refute_nil pre
    assert_includes pre, "plastic-intent-planning"
    File.write(File.join(@dir96, "plan.md"), "plan body\n")
    FileUtils.mkdir_p(File.join(@dir96, "actions"))
    File.write(File.join(@dir96, "actions", "ACTION_1.md"), "# Action 1\nreal\n")
    File.write(File.join(@dir96, "checklist.md"), "- [ ] x\n")
    assert_nil Bridge.code_gate_decision(auto_bridge, project_file, home: @home)

    # lock-gate: no lock -> deny naming intent-starting; owner -> allow.
    refute_nil gate("#{@dir97}/plan.md", session: "nobody")
    assert_includes gate("#{@dir97}/plan.md", session: "nobody"), "/plastic-intent-starting"
    assert_nil gate("#{@dir96}/plan.md", session: "a")

    # bash-gate: interpreter write into another session's locked intent -> deny
    # routed at plastic-lock; the escape tag is recognized.
    cmd = "ruby -e 'File.write(#{"#{@dir96}/plan.md".inspect}, \"x\")'"
    reason = Bridge.bash_gate_decision(nil, cmd, cwd: "/", session: "intruder")
    refute_nil reason
    assert_includes reason, "plastic-lock"
    assert Bridge.bash_escape?("#{cmd} # plastic-ok")
  end

  # --- 9-11. recovery ---------------------------------------------------------------

  def test_corrupted_bridge_recovery
    arm("a")
    File.write(Bridge.path("a", intent_id: "96", tmp: @tmp), "}{ not json")
    assert_nil gate("#{@dir96}/plan.md", session: "a"),
               "a clobbered bridge cannot strand the owner: the lock file wins (D2)"
    report = repair("a")
    assert_equal "repaired", report["status"]
    bridge = Bridge.read("a", intent_id: "96", tmp: @tmp)
    assert_equal "96", bridge.dig("intent", "id")
    assert_equal "a", bridge.dig("lock", "owner_session")
  end

  def test_corrupted_lock_recovery
    File.write(Lock.path(@dir96), "{ nope")
    reason = gate("#{@dir96}/plan.md", session: "a")
    assert_includes reason, "/plastic-doctor fix the lock"
    report = repair("a")
    assert_equal "repaired", report["status"]
    assert_equal "a", Lock.read(@dir96)["owner_session"]
    assert_nil gate("#{@dir96}/plan.md", session: "a")
  end

  def test_missing_bridge_tmp_wiped_recovery
    arm("a")
    File.delete(Bridge.path("a", intent_id: "96", tmp: @tmp))
    assert_nil gate("#{@dir96}/plan.md", session: "a"),
               "a wiped /tmp cannot strand the owner"
    report = repair("a")
    assert_equal "repaired", report["status"]
    refute_nil Bridge.read("a", intent_id: "96", tmp: @tmp), "repair rebuilds the bridge cache"
  end

  # --- 12. D9: lifecycle writes read only the MAIN store dir -----------------------

  def test_d9_lifecycle_writes_use_the_main_store_dir_not_the_store_worktree
    runner = FakeRunner.new
    bridge = provision_bridge_with(runner)
    store_wt = bridge.dig("worktree", "store")
    refute_nil store_wt

    spec = File.join(@dir96, "spec.md")
    File.write(spec, "real spec content\n")
    assert_equal "how", Bridge.derive_stage(@dir96),
                 "stage derivation reads the MAIN intent dir"
    Bridge.append_savepoint(@dir96, spec)
    assert File.exist?(File.join(@dir96, "savepoint.md")),
           "the savepoint ledger lands in the MAIN intent dir"
    refute Dir.exist?(store_wt),
           "no lifecycle op needed the store worktree even to exist on disk"
  end

  def test_d9_no_runtime_reader_consumes_the_store_worktree
    readers = Dir[File.expand_path("../../scripts/**/*", __FILE__)].select do |f|
      next false unless File.file?(f)
      src = File.read(f)
      # worktree["store"] is written at provision and removed at release;
      # nothing may READ it to locate lifecycle files.
      src.match?(/dig\(\s*["']worktree["']\s*,\s*["']store["']\s*\)|worktree\[["']store["']\]/) &&
        !f.end_with?("lib/worktree.rb")
    end
    assert_empty readers, "unexpected store-worktree consumers: #{readers}"
  end
end
