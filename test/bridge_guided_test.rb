require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "stringio"
require_relative "../scripts/lib/bridge"
require_relative "../scripts/lib/worktree"

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

  def arm_guided
    Bridge.arm_guided(@session, intent_id: "96", intent_dir: @intent_dir, store: @store, name: "demo")
  end

  def test_arm_guided_leaves_auto_false
    data = arm_guided
    assert_equal false, data["build"]["auto"]
    assert_equal "96", data["intent"]["id"]
    assert File.exist?(Bridge.path(@session))
    assert_equal false, Bridge.read(@session)["build"]["auto"]
  end

  def test_arm_guided_stamps_lock_and_calls_provision
    seen = []
    with_worktree(:provision, ->(d, *_a, **_kw) { seen << d; d["worktree"]["provisioned"] = true; d }) do
      data = arm_guided
      assert_equal data["session"], data["lock"]["owner_session"]
      assert_equal Process.pid, data["lock"]["pid"]
      refute_nil data["lock"]["acquired_at"]
      refute_nil data["lock"]["host"]
      assert_equal true, data["worktree"]["provisioned"]
    end
    assert_equal 1, seen.length, "arm_guided must call Worktree.provision exactly once"
    # lock persisted to disk
    assert_equal Process.pid, Bridge.read(@session)["lock"]["pid"]
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

  # GUARD: the shared arm helper kept arm_auto byte-identical in behaviour.
  def test_arm_auto_still_sets_auto_true_and_stamps_lock
    data = Bridge.arm_auto(@session, intent_id: "96", intent_dir: @intent_dir, store: @store, name: "demo")
    assert_equal true, data["build"]["auto"]
    assert_equal data["session"], data["lock"]["owner_session"]
    assert_equal Process.pid, data["lock"]["pid"]
    assert_equal true, Bridge.read(@session)["build"]["auto"]
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
    assert File.exist?(Bridge.path(derived))
    refute_empty out
    File.delete(Bridge.path(derived)) if File.exist?(Bridge.path(derived))
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
