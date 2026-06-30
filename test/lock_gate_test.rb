require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "socket"
require_relative "../scripts/lib/bridge"

# Pure tests for the fail-closed lock gate decision (intent 96, ACTION-2).
# No spawn: exercises Bridge.lock_gate_decision + holds_live_lock? directly.
class LockGateTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("lock-gate-home")
    @store = File.join(@home, ".plastic", "projects", "demo", "store")
    @intent_dir = File.join(@store, "96--demo")
    FileUtils.mkdir_p(@intent_dir)
    File.write(File.join(@intent_dir, "96--demo.md"), "## Intent\nDemo\n")
    @intent_file = File.join(@intent_dir, "plan.md")

    # INDEX.md lives at the PARENT of the store/ dir; intent_active? scans `## Active`.
    @index = File.join(File.dirname(@store), "INDEX.md")
    write_index_active(["96"])

    @project_file = File.join(@home, "code", "app.rb")
    FileUtils.mkdir_p(File.dirname(@project_file))
    File.write(@project_file, "puts 1\n")

    @scratch_file = File.join(@home, "scratch", "notes.txt")
    FileUtils.mkdir_p(File.dirname(@scratch_file))
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def write_index_active(ids)
    lines = ["## Active"]
    ids.each { |id| lines << "- [#{id} — demo](#{id}--demo/#{id}--demo.md)" }
    lines << ""
    lines << "## Future"
    File.write(@index, lines.join("\n") + "\n")
  end

  # A live, locally-owned bridge lock for this session, holding intent `intent_id`.
  def live_bridge(owner: "sess-1", pid: Process.pid, host: Socket.gethostname, intent_id: "96")
    {
      "session" => owner,
      "intent" => { "id" => intent_id },
      "lock" => { "owner_session" => owner, "pid" => pid, "host" => host },
    }
  end

  def decide(bridge, path)
    Bridge.lock_gate_decision(bridge, path)
  end

  # --- BLOCK paths -----------------------------------------------------------

  def test_blocks_no_lock_write_to_active_intent_dir
    refute_nil decide(nil, @intent_file), "no-lock write to active intent dir must BLOCK"
  end

  def test_block_reason_names_the_remediation
    assert_includes decide(nil, @intent_file), "/plastic-intent-starting"
  end

  def test_blocks_when_lock_is_dead_on_local_host
    dead_pid = 2**30 # an unallocated high pid
    bridge = live_bridge(pid: dead_pid)
    refute_nil decide(bridge, @intent_file), "dead local-pid lock is not held -> BLOCK"
  end

  def test_blocks_cross_intent_write_when_lock_is_for_a_different_intent
    # A live lock on intent 96, but the write targets ANOTHER active intent (97).
    other_dir = File.join(@store, "97--other")
    FileUtils.mkdir_p(other_dir)
    write_index_active(["96", "97"])
    bridge = live_bridge(intent_id: "96")
    refute_nil decide(bridge, File.join(other_dir, "plan.md")),
               "a live lock on intent 96 must NOT allow a write into intent 97's active dir"
  end

  # --- ALLOW paths -----------------------------------------------------------

  def test_allows_when_this_session_holds_a_live_lock_for_that_intent
    assert_nil decide(live_bridge(intent_id: "96"), @intent_file),
               "live lock for THIS intent -> ALLOW on its own active dir"
  end

  def test_allows_creating_a_not_yet_active_intent
    write_index_active([]) # 96 is not yet in ## Active (pre-activation / What)
    assert_nil decide(nil, @intent_file), "creating a not-yet-active intent must ALLOW (no lockout)"
  end

  def test_allows_project_code_with_no_lock
    assert_nil decide(nil, @project_file), "project code is NOT gated here (D2)"
  end

  def test_allows_scratch_path_with_no_lock
    assert_nil decide(nil, @scratch_file), "scratch outside any intent dir must ALLOW"
  end

  def test_allows_blank_file_path
    assert_nil decide(nil, "")
  end

  # --- holds_live_lock? units -----------------------------------------------

  def test_holds_live_lock_false_for_blank_owner
    refute Bridge.holds_live_lock?({ "lock" => { "owner_session" => "", "pid" => Process.pid } })
  end

  def test_holds_live_lock_false_for_nil
    refute Bridge.holds_live_lock?(nil)
  end

  def test_holds_live_lock_true_for_live_local_pid
    assert Bridge.holds_live_lock?(live_bridge)
  end

  def test_holds_live_lock_false_for_dead_local_pid
    refute Bridge.holds_live_lock?(live_bridge(pid: 2**30))
  end

  def test_holds_live_lock_true_for_foreign_host
    # A dead local pid, but stamped to a foreign host: cannot probe -> treat as held.
    bridge = live_bridge(pid: 2**30, host: "some-other-host-#{Process.pid}")
    assert Bridge.holds_live_lock?(bridge)
  end

  def test_intent_id_from_dir
    assert_equal "96", Bridge.intent_id_from_dir(@intent_dir)
    assert_nil Bridge.intent_id_from_dir("/tmp/no-double-dash")
  end
end
