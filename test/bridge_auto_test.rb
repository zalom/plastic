require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/bridge"

# Tests for the auto-mode flag added in intent 27.
class BridgeAutoTest < Minitest::Test
  def setup
    @store = Dir.mktmpdir("bridge-auto-store")
    @session = "test-#{Process.pid}-#{object_id}"
    @intent_dir = File.join(@store, "27--demo")
    FileUtils.mkdir_p(@intent_dir)
    File.write(File.join(@intent_dir, "27--demo.md"), "## Intent\nDemo\n")
  end

  def teardown
    FileUtils.rm_rf(@store)
    p = Bridge.path(@session)
    File.delete(p) if File.exist?(p)
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
end
