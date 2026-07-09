# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/bridge"
require_relative "../scripts/lib/db"

# Bridge.derive must emit the worktree + lock blocks introduced in intent 73c.
# Born unprovisioned and unowned; arm_auto fills them. Persistence moved from
# the /tmp bridge to the `sessions` table in intent 41's cutover.
class BridgeWorktreeDeriveTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("bridge-wt-home")
    @store = File.join(@home, "store")
    @intent_dir = File.join(@store, "73c1--demo")
    FileUtils.mkdir_p(@intent_dir)
    File.write(File.join(@intent_dir, "73c1--demo.md"), "## Intent\nDemo\n")
    @session = "test-#{Process.pid}-#{object_id}"
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def derive
    Bridge.derive(@session, intent_id: "73c1", intent_dir: @intent_dir,
                  store: @store, name: "demo")
  end

  def test_derive_emits_worktree_block
    wt = derive["worktree"]
    assert_equal({ "code" => nil, "code_branch" => nil, "store" => nil,
                   "store_branch" => nil, "provisioned" => false }, wt)
  end

  def test_derive_emits_lock_block
    lock = derive["lock"]
    assert_equal({ "owner_session" => nil, "acquired_at" => nil, "host" => nil,
                   "type" => nil, "delegates" => [] }, lock)
    refute lock.key?("pid"), "the lock cache never carries a pid (108 D1)"
  end

  def test_derive_persists_a_session_row
    derive
    conn = Plastic::DB.connect(@home)
    row = Plastic::DB::Sessions.active_for(conn, session: Bridge.session_key(@session, "73c1"), cwd: nil)
    refute_nil row
    assert_equal "73c1", row["active_intent_id"]
    assert_equal 0, row["auto"]
  end
end
