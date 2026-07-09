require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "stringio"
require_relative "../scripts/lib/bridge"
require_relative "../scripts/lib/worktree"
require_relative "../scripts/lib/db"

# Tests for the auto-mode flag added in intent 27. Sessions persist to the
# `sessions` table (intent 41 cutover) instead of a /tmp bridge file; the
# returned bridge_data Hash shape is unchanged, so the decision-function
# consumers (code_gate_decision etc.) keep working identically.
class BridgeAutoTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("bridge-auto-home")
    @store = File.join(@home, "store")
    @session = "test-#{Process.pid}-#{object_id}"
    @intent_dir = File.join(@store, "27--demo")
    FileUtils.mkdir_p(@intent_dir)
    File.write(File.join(@intent_dir, "27--demo.md"), "## Intent\nDemo\n")

    # Neutralize real worktree git ops by default so this suite stays hermetic
    # (no real git, no touching the real ~/.plastic). The dedicated wiring tests
    # below re-stub locally to assert arm/disarm call provision/release.
    @real_provision = Worktree.method(:provision)
    @real_release = Worktree.method(:release)
    Worktree.define_singleton_method(:provision) { |d, *_a, **_kw| d }
    Worktree.define_singleton_method(:release) { |d, *_a, **_kw| d }
  end

  def teardown
    FileUtils.rm_rf(@home)
    Worktree.define_singleton_method(:provision, @real_provision) if @real_provision
    Worktree.define_singleton_method(:release, @real_release) if @real_release
  end

  def arm
    Bridge.arm_auto(@session, intent_id: "27", intent_dir: @intent_dir, store: @store, name: "demo")
  end

  def session_row(session_id: Bridge.session_key(@session, "27"))
    conn = Plastic::DB.connect(File.dirname(@store))
    Plastic::DB::Sessions.active_for(conn, session: session_id, cwd: nil)
  end

  def lease_current(intent_id: "27")
    conn = Plastic::DB.connect(File.dirname(@store))
    Plastic::DB::Leases.current(conn, intent_id)
  end

  def test_derive_defaults_auto_false
    data = Bridge.derive(@session, intent_id: "27", intent_dir: @intent_dir, store: @store, name: "demo")
    assert_equal false, data["build"]["auto"]
  end

  def test_arm_auto_with_no_prior_bridge
    refute session_row, "no session row should exist before arming"
    data = arm
    assert_equal true, data["build"]["auto"]
    assert_equal "27", data["intent"]["id"]
    row = session_row
    refute_nil row, "arm must persist a session row"
    assert_equal 1, row["auto"]
  end

  def test_disarm_auto
    arm
    data = Bridge.disarm_auto(@session, intent_id: "27", store: @store)
    assert_equal false, data["build"]["auto"]
    assert_nil session_row, "disarm must end the session row"
  end

  def test_disarm_auto_no_bridge_is_noop
    assert_nil Bridge.disarm_auto(@session, store: @store)
  end

  # --- intent 52: session-less arming ----------------------------------------

  def test_arm_auto_uses_explicit_session
    data = Bridge.arm_auto(@session, intent_id: "27", intent_dir: @intent_dir, store: @store, name: "demo")
    assert_equal @session, data["session"]
    refute_nil session_row
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
    refute_nil session_row(session_id: Bridge.session_key(derived, "27"))
    refute_empty out
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
    # the delivery lease exists in `lock_leases` with the same owner (D2)
    assert_equal @session, lease_current["owner_session"]
  end

  def test_arm_auto_raises_lock_held_when_another_session_owns_the_lock
    conn = Plastic::DB.connect(File.dirname(@store))
    Plastic::DB::Leases.acquire(conn, "27", session: "someone-else", host: "h")
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
    refute_nil lease_current
    Bridge.disarm_auto(@session, intent_id: "27", store: @store)
    assert_nil lease_current, "disarm must clear the delivery lease (D6)"
  end

  def test_disarm_orders_worktree_release_before_lock_clear
    arm
    events = []
    # Capture as locals: define_singleton_method rebinds self, so instance
    # methods would not resolve against the test instance inside the recorder.
    still_leased = -> { !lease_current.nil? }
    recorder = ->(d, *_a, **_kw) { events << [:release, still_leased.call]; d }
    with_worktree(:release, recorder) do
      Bridge.disarm_auto(@session, intent_id: "27", store: @store)
    end
    assert_equal [[:release, true]], events,
                 "worktrees are released while the lock is STILL held (End-tail order, D6)"
  end

  def test_disarm_auto_calls_release
    arm
    seen = []
    with_worktree(:release, ->(d, *_a, **_kw) { seen << d; d.delete("worktree"); d }) do
      Bridge.disarm_auto(@session, store: @store)
    end
    assert_equal 1, seen.length, "disarm_auto must call Worktree.release exactly once"
  end

  def test_disarm_auto_survives_release_raise
    arm
    out = capture_stderr do
      with_worktree(:release, ->(*_a, **_kw) { raise "boom" }) do
        data = Bridge.disarm_auto(@session, store: @store)
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
