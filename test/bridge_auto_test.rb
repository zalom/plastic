require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "stringio"
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

  def arm
    Bridge.arm_auto(@session, intent_id: "27", intent_dir: @intent_dir, store: @store, name: "demo")
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

  def test_arm_auto_raises_lock_held_when_another_session_owns_the_lock
    Lock.acquire(@intent_dir, session: "someone-else")
    err = assert_raises(Bridge::LockHeldError) { arm }
    assert_includes err.message, "plastic-lock"
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

  def capture_stderr
    original = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = original
  end
end
