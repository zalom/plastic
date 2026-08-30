require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require_relative "../scripts/lib/arm"
require_relative "../scripts/lib/savepoint"
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

  # Arm.arm (intent 307) returns a status instead of raising; the lock, the
  # worktree stubs, and the tmp home are the same surface the bridge era armed.
  def arm(session, id: "96", dir: @dir96, auto: false)
    Arm.arm(intent_dir: dir, session: session, mode: auto ? "auto" : "guided", home: @home)
  end

  def repair(session)
    Arm.repair(intent_dir: @dir96, session: session, home: @home)
  end

  # --- 1. single owner ---------------------------------------------------------

  def test_single_owner_second_session_refused_owner_idempotent
    arm("a")
    refused = arm("b")
    assert_equal :held, refused[:status]
    assert_equal "a", refused[:lock]["owner_session"]

    data = arm("a") # idempotent re-arm, :owned path
    assert_equal :owned, data[:status]
    assert_equal "a", data[:lock]["owner_session"]
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

  def test_delegate_holds_the_lock_and_a_stranger_does_not
    arm("owner-a")
    assert Lock.add_delegate(@dir96, delegate: "sub", session: "owner-a")
    assert Lock.holds?(@dir96, session: "sub")
    refute Lock.holds?(@dir96, session: "stranger")
  end

  # --- 4. session resolution: all three fallbacks -------------------------------

  def test_explicit_session_keys_the_lock
    arm("explicit-sid")
    assert_equal "explicit-sid", Lock.read(@dir96)["owner_session"]
  end

  def test_env_session_keys_the_lock_when_no_explicit
    # Arm reads no environment: the env id is an argument (intent 307), so the
    # CLI is what passes CLAUDE_CODE_SESSION_ID through. The library contract
    # is the resolution order itself.
    key = Arm.resolve_session(nil, env: "env-sid", store: @store, intent_id: "96")
    assert_equal "env-sid", key
    Arm.arm(intent_dir: @dir96, session: key, mode: "guided", home: @home)
    assert_equal "env-sid", Lock.read(@dir96)["owner_session"]
  end

  def test_derived_key_when_both_blank
    derived = Arm.derive_key(@store, "96")
    result = arm(nil)
    assert_equal derived, Lock.read(@dir96)["owner_session"]
    assert_nil result[:pointer], "a derived key gets no session pointer: no hook would read it"
  end

  # --- 5. concurrent parallel sessions ------------------------------------------

  def test_two_sessions_hold_their_own_intents_cross_denied
    arm("a", id: "96", dir: @dir96)
    arm("b", id: "97", dir: @dir97)

    assert Lock.holds?(@dir96, session: "a")
    assert Lock.holds?(@dir97, session: "b")
    refute Lock.holds?(@dir96, session: "b"), "b does not hold a's intent"
    refute Lock.holds?(@dir97, session: "a"), "a does not hold b's intent"

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

    bridge["session"] = "a"

    # Merge-remove: finish(merge: true) merges the code branch, then removes
    # the worktree and clears the block.
    finish_runner = FakeRunner.new
    result = with_real_worktree do
      Worktree.finish(bridge, home: @home, runner: finish_runner, merge: true)
    end
    merges = finish_runner.calls.select { |c| c.include?("merge") }
    removes = finish_runner.calls.select { |c| c.include?("remove") }
    refute_empty merges, "finish(merge: true) must merge the code branch"
    assert_equal 1, removes.length, "the code worktree is removed"
    assert_nil result["worktree"]
  end

  # --- 9-11. recovery ---------------------------------------------------------------

  def test_corrupted_lock_recovery
    File.write(Lock.path(@dir96), "{ nope")
    assert Lock.corrupt?(@dir96)
    report = repair("a")
    assert_equal "repaired", report["status"]
    assert_equal "a", Lock.read(@dir96)["owner_session"]
    assert Lock.holds?(@dir96, session: "a")
  end

  # --- 12. D9: lifecycle writes read only the MAIN store dir -----------------------

  # Intent 178 retired the store worktree entirely, so `provision` no longer
  # carries a "store" key at all (proven directly in
  # test/worktree_test.rb#test_provision_does_not_create_a_store_worktree).
  # What is left of D9's guarantee, and still worth proving here, is that
  # lifecycle writes land in the MAIN intent dir regardless.
  def test_d9_lifecycle_writes_use_the_main_store_dir
    runner = FakeRunner.new
    bridge = provision_bridge_with(runner)
    refute bridge["worktree"].key?("store"), "provision must not carry a store key at all"

    spec = File.join(@dir96, "spec.md")
    File.write(spec, "real spec content\n")
    assert_equal "how", Savepoint.derive_stage(@dir96),
                 "stage derivation reads the MAIN intent dir"
    Savepoint.append_savepoint(@dir96, spec)
    assert File.exist?(File.join(@dir96, "savepoint.md")),
           "the savepoint ledger lands in the MAIN intent dir"
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
