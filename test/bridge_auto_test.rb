require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "stringio"
require "json"
require_relative "../scripts/lib/bridge"
require_relative "../scripts/lib/worktree"
require_relative "../scripts/lib/lock"

# Tests for the auto-mode flag added in intent 27.
class BridgeAutoTest < Minitest::Test
  def setup
    @store = Dir.mktmpdir("bridge-auto-store")
    @session = "test-#{Process.pid}-#{object_id}"
    @intent_dir = File.join(@store, "27--demo")
    FileUtils.mkdir_p(@intent_dir)
    File.write(File.join(@intent_dir, "27--demo.md"), "## Intent\nDemo\n")
    @bridge_tmp = Dir.mktmpdir("bridge-auto-tmp")
    @saved_plastic_tmp = ENV["PLASTIC_TMP"]
    ENV["PLASTIC_TMP"] = @bridge_tmp

    # Neutralize real worktree git ops by default so this suite stays hermetic
    # (no real git, no touching the real ~/.plastic). The dedicated wiring tests
    # below re-stub locally to assert arm/disarm call provision/release.
    @real_provision = Worktree.method(:provision)
    @real_release = Worktree.method(:release)
    Worktree.define_singleton_method(:provision) { |d, *_a, **_kw| d }
    Worktree.define_singleton_method(:release) { |d, *_a, **_kw| d }
  end

  def teardown
    FileUtils.rm_rf(@store)
    FileUtils.rm_rf(@bridge_tmp)
    @saved_plastic_tmp.nil? ? ENV.delete("PLASTIC_TMP") : ENV["PLASTIC_TMP"] = @saved_plastic_tmp
    Worktree.define_singleton_method(:provision, @real_provision) if @real_provision
    Worktree.define_singleton_method(:release, @real_release) if @real_release
  end

  def arm(harness: nil)
    Bridge.arm_auto(@session, intent_id: "27", intent_dir: @intent_dir, store: @store,
                    name: "demo", harness: harness)
  end

  def test_derive_defaults_auto_false
    data = Bridge.derive(@session, intent_id: "27", intent_dir: @intent_dir, store: @store, name: "demo")
    assert_equal false, data["build"]["auto"]
  end

  def test_arm_auto_with_no_prior_bridge
    refute File.exist?(Bridge.path(@session, intent_id: "27"))
    data = arm
    assert_equal true, data["build"]["auto"]
    assert_equal "27", data["intent"]["id"]
    assert File.exist?(Bridge.path(@session, intent_id: "27"))
    # persisted
    assert_equal true, Bridge.read(@session, intent_id: "27")["build"]["auto"]
    assert_nil Lock.read(@intent_dir)["owner_harness"]
    assert_nil Lock.read(@intent_dir)["owner_agent"]
  end

  def test_disarm_auto
    arm
    data = Bridge.disarm_auto(@session, intent_id: "27")
    assert_equal false, data["build"]["auto"]
    assert_equal false, Bridge.read(@session, intent_id: "27")["build"]["auto"]
  end

  def test_disarm_auto_no_bridge_is_noop
    assert_nil Bridge.disarm_auto(@session)
  end

  # --- intent 52: session-less arming ----------------------------------------

  def test_arm_auto_uses_explicit_session
    data = Bridge.arm_auto(@session, intent_id: "27", intent_dir: @intent_dir, store: @store, name: "demo")
    assert_equal @session, data["session"]
    assert File.exist?(Bridge.path(@session, intent_id: "27"))
  end

  def test_arm_auto_derives_key_and_warns_when_no_session
    saved_code = ENV["CLAUDE_CODE_SESSION_ID"]
    # "No session available" means the session env var is blank (intent 79): the
    # CLAUDE_CODE_SESSION_ID fallback must also be absent to reach the derive path.
    ENV.delete("CLAUDE_CODE_SESSION_ID")
    derived = Bridge.derive_key(@store, "27")
    out = capture_stderr do
      data = Bridge.arm_auto(nil, intent_id: "27", intent_dir: @intent_dir, store: @store, name: "demo")
      assert_equal derived, data["session"]
    end
    assert File.exist?(Bridge.path(derived, intent_id: "27"))
    refute_empty out
    File.delete(Bridge.path(derived, intent_id: "27")) if File.exist?(Bridge.path(derived, intent_id: "27"))
  ensure
    ENV["CLAUDE_CODE_SESSION_ID"] = saved_code unless saved_code.nil?
  end

  def test_arm_auto_does_not_warn_when_env_session_present
    saved = ENV["CLAUDE_CODE_SESSION_ID"]
    ENV["CLAUDE_CODE_SESSION_ID"] = "env-#{Process.pid}"
    out = capture_stderr do
      data = Bridge.arm_auto(nil, intent_id: "27", intent_dir: @intent_dir, store: @store, name: "demo")
      assert_equal ENV["CLAUDE_CODE_SESSION_ID"], data["session"]
    end
    assert_empty out.strip
    p = Bridge.path("env-#{Process.pid}", intent_id: "27")
    File.delete(p) if File.exist?(p)
  ensure
    if saved.nil?
      ENV.delete("CLAUDE_CODE_SESSION_ID")
    else
      ENV["CLAUDE_CODE_SESSION_ID"] = saved
    end
  end

  # --- intent 73c: worktree provision + delivery lock wiring -----------------

  # Temporarily redefine a Worktree singleton method for one block, restoring it
  # after. (Minitest::Mock#stub is unavailable in this bundled minitest, so we
  # use the same define_singleton_method seam the setup uses.)
  def with_worktree(method_name, impl)
    original = Worktree.method(method_name)
    Worktree.define_singleton_method(method_name, impl)
    yield
  ensure
    Worktree.define_singleton_method(method_name, original)
  end

  # Temporarily redefine Lock.release for one block, restoring it after. Same
  # define_singleton_method seam with_worktree uses (this bundled minitest has
  # no Minitest::Mock#stub). Needed only for the raising case: :released,
  # :not_owner, and :none are all produced with real files, no stub.
  def with_lock_release(impl)
    original = Lock.method(:release)
    Lock.define_singleton_method(:release, impl)
    yield
  ensure
    Lock.define_singleton_method(:release, original)
  end

  # Rewrite the real delivery.lock so a different session owns it. Real
  # Lock.release then returns :not_owner; no stub involved.
  def steal_lock(owner)
    p = Lock.path(@intent_dir)
    data = JSON.parse(File.read(p))
    data["owner_session"] = owner
    File.write(p, JSON.generate(data))
  end

  # arm_auto must acquire the durable delivery lock (owner=key, timestamp, host,
  # never a pid) and call Worktree.provision. We swap provision so no real git
  # runs; the swap records the call and stamps a marker we can assert on.
  def test_arm_auto_sets_lock_and_calls_provision
    seen = []
    with_worktree(:provision, ->(d, *_a, **_kw) { seen << d; d["worktree"]["provisioned"] = true; d }) do
      data = arm
      assert_equal data["session"], data["lock"]["owner_session"]
      refute data["lock"].key?("pid"), "the lock cache never carries a pid (108 D1)"
      refute_nil data["lock"]["acquired_at"]
      refute_nil data["lock"]["host"]
      assert_equal true, data["worktree"]["provisioned"]
    end
    assert_equal 1, seen.length, "arm_auto must call Worktree.provision exactly once"
    # lock cache persisted to disk, and the durable lock file exists in the
    # intent dir with the same owner (the file is the truth, D2)
    assert_equal @session, Bridge.read(@session, intent_id: "27")["lock"]["owner_session"]
    assert_equal @session, Lock.read(@intent_dir)["owner_session"]
  end

  def test_codex_boarding_records_enforcer_harness_thread_and_mode
    data = Bridge.arm_auto(@session, intent_id: "27", intent_dir: @intent_dir,
                           store: @store, name: "demo", harness: :codex,
                           agent: "plastic-enforcer", model: "gpt-5", thread: "thread-27")
    expected = {
      "owner_harness" => "codex",
      "owner_agent" => "plastic-enforcer",
      "owner_model" => "gpt-5",
      "owner_thread" => "thread-27",
      "run_mode" => "auto",
    }
    expected.each do |field, value|
      assert_equal value, Lock.read(@intent_dir)[field]
      assert_equal value, data.dig("lock", field)
    end
  end

  def test_arm_auto_raises_lock_held_when_another_session_owns_the_lock
    Lock.acquire(@intent_dir, session: "someone-else")
    err = assert_raises(Bridge::LockHeldError) { arm }
    assert_includes err.message, "/plastic-doctor"
  end

  def test_arm_auto_raises_lock_held_naming_dollar_prefix_for_codex_harness
    Lock.acquire(@intent_dir, session: "someone-else")
    err = assert_raises(Bridge::LockHeldError) { arm(harness: :codex) }
    assert_includes err.message, "$plastic-doctor"
    refute_includes err.message, "/plastic-doctor"
  end

  def test_arm_auto_survives_provision_raise
    out = capture_stderr do
      with_worktree(:provision, ->(*_a, **_kw) { raise "boom" }) do
        data = arm
        assert_equal true, data["build"]["auto"], "auto still armed despite provision failure"
        assert_equal data["session"], data["lock"]["owner_session"]
      end
    end
    refute_empty out
  end

  # --- intent 230: the bridge is written once, after lock + worktree settle ---

  # Seed a bridge on disk that carries a real worktree pointer, the way a live
  # armed session would.
  def seed_bridge_with_pointer(code_dir)
    data = Bridge.derive(@session, intent_id: "27", intent_dir: @intent_dir,
                         store: @store, name: "demo")
    data["worktree"] = { "code" => code_dir, "code_branch" => "plastic/27--demo",
                         "provisioned" => true }
    Bridge.write(@session, data)
    data
  end

  def test_arm_auto_leaves_the_on_disk_bridge_untouched_when_the_lock_is_held
    code_dir = File.join(@store, "fake-worktree")
    FileUtils.mkdir_p(code_dir)
    seed_bridge_with_pointer(code_dir)
    before = File.read(Bridge.path(@session, intent_id: "27"))

    Lock.acquire(@intent_dir, session: "someone-else")
    assert_raises(Bridge::LockHeldError) { arm }

    assert_equal before, File.read(Bridge.path(@session, intent_id: "27")),
                 "a failed lock must not rewrite the bridge (intent 230)"
  end

  def test_arm_auto_writes_no_bridge_at_all_when_the_lock_is_held
    refute File.exist?(Bridge.path(@session, intent_id: "27"))
    Lock.acquire(@intent_dir, session: "someone-else")
    assert_raises(Bridge::LockHeldError) { arm }
    refute File.exist?(Bridge.path(@session, intent_id: "27")),
           "no bridge may exist without a lock behind it (intent 230)"
  end

  def test_arm_auto_keeps_the_existing_worktree_pointer_when_provision_raises
    code_dir = File.join(@store, "fake-worktree")
    FileUtils.mkdir_p(code_dir)
    seed_bridge_with_pointer(code_dir)

    capture_stderr do
      with_worktree(:provision, ->(*_a, **_kw) { raise "boom" }) { arm }
    end

    persisted = Bridge.read(@session, intent_id: "27")["worktree"]
    assert_equal code_dir, persisted["code"],
                 "a failed provision must not erase a live worktree pointer"
  end

  def test_disarm_clears_the_delivery_lock
    arm
    assert File.exist?(Lock.path(@intent_dir))
    Bridge.disarm_auto(@session, intent_id: "27")
    refute File.exist?(Lock.path(@intent_dir)), "disarm must clear delivery.lock (D6)"
    data = Bridge.read(@session, intent_id: "27")
    assert_nil data.dig("lock", "owner_session"), "the bridge cache is cleared too"
  end

  def test_disarm_orders_worktree_release_before_lock_clear
    arm
    events = []
    # Capture as a local: define_singleton_method rebinds self, so instance
    # variables would resolve against Worktree inside the recorder.
    lock_path = Lock.path(@intent_dir)
    recorder = ->(d, *_a, **_kw) { events << [:release, File.exist?(lock_path)]; d }
    with_worktree(:release, recorder) do
      Bridge.disarm_auto(@session, intent_id: "27")
    end
    assert_equal [[:release, true]], events,
                 "worktrees are released while the lock is STILL held (End-tail order, D6)"
  end

  def test_disarm_auto_calls_release
    arm
    seen = []
    with_worktree(:release, ->(d, *_a, **_kw) { seen << d; d.delete("worktree"); d }) do
      Bridge.disarm_auto(@session)
    end
    assert_equal 1, seen.length, "disarm_auto must call Worktree.release exactly once"
  end

  def test_disarm_auto_survives_release_raise
    arm
    out = capture_stderr do
      with_worktree(:release, ->(*_a, **_kw) { raise "boom" }) do
        data = Bridge.disarm_auto(@session)
        assert_equal false, data["build"]["auto"]
      end
    end
    refute_empty out
  end

  # --- intent 233: disarm branches on the lock release result -----------------

  def test_disarm_blanks_the_lock_cache_when_the_release_succeeds
    arm
    data = Bridge.disarm_auto(@session, intent_id: "27")
    refute_nil data
    assert_nil data["lock"]["owner_session"]
    assert_nil data["lock"]["acquired_at"]
    assert_nil data["lock"]["host"]
    assert_nil data["lock"]["type"]
    assert_equal [], data["lock"]["delegates"]
    assert_equal "released", data["lock"]["release_status"]
    refute File.exist?(Lock.path(@intent_dir))
    persisted = Bridge.read(@session, intent_id: "27")
    assert_nil persisted["lock"]["owner_session"]
  end

  def test_disarm_preserves_the_lock_cache_when_the_release_is_not_owner
    arm
    steal_lock("foreign-#{Process.pid}")
    out = capture_stderr { @data = Bridge.disarm_auto(@session, intent_id: "27") }
    assert_equal @session, @data.dig("lock", "owner_session")
    assert File.exist?(Lock.path(@intent_dir))
    assert_includes out, @intent_dir
    assert_includes out, "not_owner"
    assert_equal "not_owner", @data.dig("lock", "release_status")
    assert_equal false, @data["build"]["auto"]
    assert_equal @session, Bridge.read(@session, intent_id: "27").dig("lock", "owner_session")
  end

  def test_disarm_preserves_the_lock_cache_when_the_release_raises
    arm
    out = capture_stderr do
      with_lock_release(->(*_a, **_kw) { raise "boom" }) do
        @data = Bridge.disarm_auto(@session, intent_id: "27")
      end
    end
    assert_equal @session, @data.dig("lock", "owner_session")
    assert File.exist?(Lock.path(@intent_dir))
    refute_empty out
    assert_includes out, @intent_dir
    assert_equal "raised", @data.dig("lock", "release_status")
    assert_equal false, @data["build"]["auto"]
  end

  def test_disarm_treats_a_missing_lock_as_a_successful_release
    arm
    File.delete(Lock.path(@intent_dir))
    out = capture_stderr { @data = Bridge.disarm_auto(@session, intent_id: "27") }
    assert_nil @data.dig("lock", "owner_session")
    assert_equal "none", @data.dig("lock", "release_status")
    assert_empty out.strip
  end

  def test_disarm_still_purges_and_returns_after_a_failed_release
    arm
    steal_lock("foreign-#{Process.pid}")
    result = nil
    capture_stderr do
      with_worktree(:release, ->(d, *_a, **_kw) { d }) do
        result = Bridge.disarm_auto(@session, intent_id: "27")
      end
    end
    assert_kind_of Hash, result
    refute_nil Bridge.read(@session, intent_id: "27")
    File.delete(Lock.path(@intent_dir)) if File.exist?(Lock.path(@intent_dir))
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
