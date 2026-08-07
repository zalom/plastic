require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "stringio"
require_relative "../scripts/lib/bridge"
require_relative "../scripts/lib/worktree"
require_relative "../scripts/lib/lock"

# Tests for arm_guided: acquire the delivery lock WITHOUT auto mode (intent 96).
# Mirrors bridge_auto_test.rb's hermetic setup exactly.
class BridgeGuidedTest < Minitest::Test
  def setup
    @store = Dir.mktmpdir("bridge-guided-store")
    @session = "test-#{Process.pid}-#{object_id}"
    @intent_dir = File.join(@store, "96--demo")
    FileUtils.mkdir_p(@intent_dir)
    File.write(File.join(@intent_dir, "96--demo.md"), "## Intent\nDemo\n")
    @bridge_tmp = Dir.mktmpdir("bridge-guided-tmp")
    @saved_plastic_tmp = ENV["PLASTIC_TMP"]
    ENV["PLASTIC_TMP"] = @bridge_tmp

    # Neutralize real worktree git ops by default so this suite stays hermetic.
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

  # Temporarily redefine a Worktree singleton method for one block, restoring it
  # after (the sanctioned seam; bundled Minitest has no #stub).
  def with_worktree(method_name, impl)
    original = Worktree.method(method_name)
    Worktree.define_singleton_method(method_name, impl)
    yield
  ensure
    Worktree.define_singleton_method(method_name, original)
  end

  def arm_guided(harness: nil)
    Bridge.arm_guided(@session, intent_id: "96", intent_dir: @intent_dir, store: @store,
                      name: "demo", harness: harness)
  end

  def test_arm_guided_leaves_auto_false
    data = arm_guided
    assert_equal false, data["build"]["auto"]
    assert_equal "96", data["intent"]["id"]
    assert File.exist?(Bridge.path(@session, intent_id: "96"))
    assert_equal false, Bridge.read(@session, intent_id: "96")["build"]["auto"]
    assert_nil Lock.read(@intent_dir)["owner_harness"]
    assert_nil Lock.read(@intent_dir)["owner_agent"]
  end

  def test_arm_guided_stamps_lock_and_calls_provision
    seen = []
    with_worktree(:provision, ->(d, *_a, **_kw) { seen << d; d["worktree"]["provisioned"] = true; d }) do
      data = arm_guided
      assert_equal data["session"], data["lock"]["owner_session"]
      refute data["lock"].key?("pid"), "the lock cache never carries a pid (108 D1)"
      refute_nil data["lock"]["acquired_at"]
      refute_nil data["lock"]["host"]
      assert_equal true, data["worktree"]["provisioned"]
    end
    assert_equal 1, seen.length, "arm_guided must call Worktree.provision exactly once"
    # lock cache persisted to disk, and the durable lock file exists in the
    # intent dir with the same owner (the file is the truth, D2)
    assert_equal @session, Bridge.read(@session, intent_id: "96")["lock"]["owner_session"]
    assert_equal @session, Lock.read(@intent_dir)["owner_session"]
  end

  def test_claude_boarding_records_enforcer_harness_without_guessing_thread
    data = Bridge.arm_guided(@session, intent_id: "96", intent_dir: @intent_dir,
                             store: @store, name: "demo", harness: :claude,
                             agent: "plastic-enforcer", model: "opus")
    expected = {
      "owner_harness" => "claude",
      "owner_agent" => "plastic-enforcer",
      "owner_model" => "opus",
      "run_mode" => "guided",
    }
    expected.each do |field, value|
      assert_equal value, Lock.read(@intent_dir)[field]
      assert_equal value, data.dig("lock", field)
    end
    assert_nil Lock.read(@intent_dir)["owner_thread"]
    assert_nil data.dig("lock", "owner_thread")
  end

  def test_arm_guided_raises_lock_held_when_another_session_owns_the_lock
    Lock.acquire(@intent_dir, session: "someone-else")
    err = assert_raises(Bridge::LockHeldError) { arm_guided }
    assert_includes err.message, "/plastic-doctor"
  end

  def test_arm_guided_raises_lock_held_naming_dollar_prefix_for_codex_harness
    Lock.acquire(@intent_dir, session: "someone-else")
    err = assert_raises(Bridge::LockHeldError) { arm_guided(harness: :codex) }
    assert_includes err.message, "$plastic-doctor"
    refute_includes err.message, "/plastic-doctor"
  end

  def test_arm_guided_survives_provision_raise
    out = capture_stderr do
      with_worktree(:provision, ->(*_a, **_kw) { raise "boom" }) do
        data = arm_guided
        assert_equal false, data["build"]["auto"], "auto stays false despite provision failure"
        assert_equal data["session"], data["lock"]["owner_session"]
      end
    end
    refute_empty out
  end

  # --- intent 230 ---

  def test_arm_guided_leaves_the_on_disk_bridge_untouched_when_the_lock_is_held
    data = Bridge.derive(@session, intent_id: "96", intent_dir: @intent_dir,
                         store: @store, name: "demo")
    code_dir = File.join(@store, "fake-worktree")
    FileUtils.mkdir_p(code_dir)
    data["worktree"] = { "code" => code_dir, "code_branch" => "plastic/96--demo",
                         "provisioned" => true }
    Bridge.write(@session, data)
    before = File.read(Bridge.path(@session, intent_id: "96"))

    Lock.acquire(@intent_dir, session: "someone-else")
    assert_raises(Bridge::LockHeldError) { arm_guided }

    assert_equal before, File.read(Bridge.path(@session, intent_id: "96")),
                 "a failed lock must not rewrite the bridge (intent 230)"
  end

  # GUARD: the shared arm helper kept arm_auto byte-identical in behaviour.
  def test_arm_auto_still_sets_auto_true_and_stamps_lock
    data = Bridge.arm_auto(@session, intent_id: "96", intent_dir: @intent_dir, store: @store, name: "demo")
    assert_equal true, data["build"]["auto"]
    assert_equal data["session"], data["lock"]["owner_session"]
    assert_equal @session, Lock.read(@intent_dir)["owner_session"]
    assert_equal true, Bridge.read(@session, intent_id: "96")["build"]["auto"]
  end

  # Session-less arming derives the key, writes the bridge, warns on stderr.
  def test_arm_guided_derives_key_and_warns_when_no_session
    saved_code = ENV["CLAUDE_CODE_SESSION_ID"]
    ENV.delete("CLAUDE_CODE_SESSION_ID")
    derived = Bridge.derive_key(@store, "96")
    out = capture_stderr do
      data = Bridge.arm_guided(nil, intent_id: "96", intent_dir: @intent_dir, store: @store, name: "demo")
      assert_equal derived, data["session"]
      assert_equal false, data["build"]["auto"]
    end
    assert File.exist?(Bridge.path(derived, intent_id: "96"))
    refute_empty out
    File.delete(Bridge.path(derived, intent_id: "96")) if File.exist?(Bridge.path(derived, intent_id: "96"))
  ensure
    ENV["CLAUDE_CODE_SESSION_ID"] = saved_code unless saved_code.nil?
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
