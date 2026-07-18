# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/bridge"

# Bridge.derive must emit the worktree + lock blocks introduced in intent 73c.
# Born unprovisioned and unowned; arm_auto fills them.
class BridgeWorktreeDeriveTest < Minitest::Test
  def setup
    @store = Dir.mktmpdir("bridge-wt-store")
    @intent_dir = File.join(@store, "73c1--demo")
    FileUtils.mkdir_p(@intent_dir)
    File.write(File.join(@intent_dir, "73c1--demo.md"), "## Intent\nDemo\n")
    @session = "test-#{Process.pid}-#{object_id}"
    @bridge_tmp = Dir.mktmpdir("bridge-wt-tmp")
    @saved = ENV["PLASTIC_TMP"]
    ENV["PLASTIC_TMP"] = @bridge_tmp
  end

  def teardown
    FileUtils.rm_rf(@store)
    FileUtils.rm_rf(@bridge_tmp)
    @saved.nil? ? ENV.delete("PLASTIC_TMP") : ENV["PLASTIC_TMP"] = @saved
  end

  def derive
    Bridge.derive(@session, intent_id: "73c1", intent_dir: @intent_dir,
                  store: @store, name: "demo")
  end

  def test_derive_emits_worktree_block
    wt = derive["worktree"]
    assert_equal({ "code" => nil, "code_branch" => nil, "provisioned" => false }, wt)
  end

  def test_derive_emits_lock_block
    lock = derive["lock"]
    assert_equal({ "owner_session" => nil, "acquired_at" => nil, "host" => nil,
                   "type" => nil, "delegates" => [] }, lock)
    refute lock.key?("pid"), "the lock cache never carries a pid (108 D1)"
  end

  def test_derive_blocks_persist_to_disk
    derive
    data = Bridge.read(@session, intent_id: "73c1")
    assert data.key?("worktree")
    assert data.key?("lock")
    assert_equal false, data["worktree"]["provisioned"]
  end
end
