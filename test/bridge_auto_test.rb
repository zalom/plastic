require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "stringio"
require_relative "../scripts/lib/bridge"

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
  end

  def teardown
    FileUtils.rm_rf(@store)
    FileUtils.rm_rf(@bridge_tmp)
    @saved_plastic_tmp.nil? ? ENV.delete("PLASTIC_TMP") : ENV["PLASTIC_TMP"] = @saved_plastic_tmp
  end

  def arm
    Bridge.arm_auto(@session, intent_id: "27", intent_dir: @intent_dir, store: @store, name: "demo")
  end

  def test_derive_defaults_auto_false
    data = Bridge.derive(@session, intent_id: "27", intent_dir: @intent_dir, store: @store, name: "demo")
    assert_equal false, data["build"]["auto"]
  end

  def test_arm_auto_with_no_prior_bridge
    refute File.exist?(Bridge.path(@session))
    data = arm
    assert_equal true, data["build"]["auto"]
    assert_equal "27", data["intent"]["id"]
    assert File.exist?(Bridge.path(@session))
    # persisted
    assert_equal true, Bridge.read(@session)["build"]["auto"]
  end

  def test_disarm_auto
    arm
    data = Bridge.disarm_auto(@session)
    assert_equal false, data["build"]["auto"]
    assert_equal false, Bridge.read(@session)["build"]["auto"]
  end

  def test_disarm_auto_no_bridge_is_noop
    assert_nil Bridge.disarm_auto(@session)
  end

  # --- intent 52: session-less arming ----------------------------------------

  def test_arm_auto_uses_explicit_session
    data = Bridge.arm_auto(@session, intent_id: "27", intent_dir: @intent_dir, store: @store, name: "demo")
    assert_equal @session, data["session"]
    assert File.exist?(Bridge.path(@session))
  end

  def test_arm_auto_derives_key_and_warns_when_no_session
    saved = ENV["CLAUDE_SESSION_ID"]
    saved_code = ENV["CLAUDE_CODE_SESSION_ID"]
    ENV.delete("CLAUDE_SESSION_ID")
    # "No session available" now means BOTH env vars blank (intent 79): the
    # CLAUDE_CODE_SESSION_ID fallback must also be absent to reach the derive path.
    ENV.delete("CLAUDE_CODE_SESSION_ID")
    derived = Bridge.derive_key(@store, "27")
    out = capture_stderr do
      data = Bridge.arm_auto(nil, intent_id: "27", intent_dir: @intent_dir, store: @store, name: "demo")
      assert_equal derived, data["session"]
    end
    assert File.exist?(Bridge.path(derived))
    refute_empty out
    File.delete(Bridge.path(derived)) if File.exist?(Bridge.path(derived))
  ensure
    ENV["CLAUDE_SESSION_ID"] = saved unless saved.nil?
    ENV["CLAUDE_CODE_SESSION_ID"] = saved_code unless saved_code.nil?
  end

  def test_arm_auto_does_not_warn_when_env_session_present
    saved = ENV["CLAUDE_SESSION_ID"]
    ENV["CLAUDE_SESSION_ID"] = "env-#{Process.pid}"
    out = capture_stderr do
      data = Bridge.arm_auto(nil, intent_id: "27", intent_dir: @intent_dir, store: @store, name: "demo")
      assert_equal ENV["CLAUDE_SESSION_ID"], data["session"]
    end
    assert_empty out.strip
    p = Bridge.path("env-#{Process.pid}")
    File.delete(p) if File.exist?(p)
  ensure
    if saved.nil?
      ENV.delete("CLAUDE_SESSION_ID")
    else
      ENV["CLAUDE_SESSION_ID"] = saved
    end
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
