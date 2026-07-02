require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "rbconfig"
require_relative "../scripts/lib/bridge"
require_relative "../scripts/lib/lock"

# Pure tests for the fail-closed lock gate decision (intents 96 + 108).
# The gate decides from the durable delivery.lock in the TARGET intent dir;
# bridges only supply a fallback session id. No pid is consulted anywhere.
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

  # --- ALLOW: the lock FILE decides (D2) --------------------------------------

  def test_owner_session_with_lock_file_is_allowed
    Lock.acquire(@intent_dir, session: "sess-1")
    bridge = { "session" => "sess-1", "intent" => { "id" => "96" } }
    assert_nil Bridge.lock_gate_decision(bridge, @intent_file, session: "sess-1")
  end

  def test_allowed_even_when_bridge_is_missing_lock_file_wins
    Lock.acquire(@intent_dir, session: "sess-1")
    assert_nil Bridge.lock_gate_decision(nil, @intent_file, session: "sess-1"),
               "a wiped /tmp must not strand the owner: the lock FILE decides (D2)"
  end

  def test_allowed_even_when_bridge_disagrees_lock_file_wins
    Lock.acquire(@intent_dir, session: "sess-1")
    stale_bridge = { "session" => "sess-1", "intent" => { "id" => "1" },
                     "lock" => { "owner_session" => "someone-else" } }
    assert_nil Bridge.lock_gate_decision(stale_bridge, @intent_file, session: "sess-1")
  end

  def test_owner_allowed_on_its_own_stale_lock
    Lock.acquire(@intent_dir, session: "sess-1")
    FileUtils.touch(Lock.path(@intent_dir), mtime: Time.now - 4000)
    assert_nil Bridge.lock_gate_decision(nil, @intent_file, session: "sess-1"),
               "a stale lock is still the owner's until an explicit takeover"
  end

  def test_session_falls_back_to_the_bridge_session
    Lock.acquire(@intent_dir, session: "sess-1")
    bridge = { "session" => "sess-1", "intent" => { "id" => "96" } }
    assert_nil Bridge.lock_gate_decision(bridge, @intent_file),
               "with no explicit session the bridge supplies the session id"
  end

  # --- delegation (D4) ---------------------------------------------------------

  def test_delegate_is_allowed_non_delegate_denied
    Lock.acquire(@intent_dir, session: "owner")
    Lock.add_delegate(@intent_dir, delegate: "sub-1", session: "owner")
    assert_nil Bridge.lock_gate_decision(nil, @intent_file, session: "sub-1")
    reason = Bridge.lock_gate_decision(nil, @intent_file, session: "stranger")
    refute_nil reason
    assert_includes reason, "plastic-lock delegate"
  end

  # --- deny routing (D5): every deny names the resolving command ---------------

  def test_no_lock_deny_names_intent_starting
    assert_includes Bridge.lock_gate_decision(nil, @intent_file, session: "s"),
                    "/plastic-intent-starting"
  end

  def test_stale_lock_deny_names_reclaim
    Lock.acquire(@intent_dir, session: "other")
    FileUtils.touch(Lock.path(@intent_dir), mtime: Time.now - 4000)
    reason = Bridge.lock_gate_decision(nil, @intent_file, session: "sess-1")
    assert_includes reason, "/plastic-lock reclaim"
  end

  def test_corrupt_lock_deny_names_fix
    File.write(Lock.path(@intent_dir), "{ nope")
    reason = Bridge.lock_gate_decision(nil, @intent_file, session: "sess-1")
    assert_includes reason, "/plastic-lock fix"
  end

  def test_fresh_foreign_lock_denies_and_names_status
    Lock.acquire(@intent_dir, session: "other")
    reason = Bridge.lock_gate_decision(nil, @intent_file, session: "sess-1")
    refute_nil reason
    assert_includes reason, "/plastic-lock status"
  end

  # --- scope: allow-by-lock is per-intent --------------------------------------

  def test_blocks_cross_intent_write_when_lock_is_for_a_different_intent
    other_dir = File.join(@store, "97--demo")
    FileUtils.mkdir_p(other_dir)
    write_index_active(["96", "97"])
    Lock.acquire(@intent_dir, session: "sess-1")
    refute_nil Bridge.lock_gate_decision(nil, File.join(other_dir, "plan.md"), session: "sess-1"),
               "a lock on intent 96 must NOT allow a write into intent 97's active dir"
  end

  # --- ALLOW: paths the gate does not govern -----------------------------------

  def test_allows_creating_a_not_yet_active_intent
    write_index_active([]) # 96 is not yet in ## Active (pre-activation / What)
    assert_nil Bridge.lock_gate_decision(nil, @intent_file, session: "s"),
               "creating a not-yet-active intent must ALLOW (no lockout)"
  end

  def test_allows_project_code_with_no_lock
    assert_nil Bridge.lock_gate_decision(nil, @project_file, session: "s"),
               "project code is NOT gated here (D2)"
  end

  def test_allows_scratch_path_with_no_lock
    assert_nil Bridge.lock_gate_decision(nil, @scratch_file, session: "s")
  end

  def test_allows_blank_file_path
    assert_nil Bridge.lock_gate_decision(nil, "", session: "s")
  end

  # --- holds_live_lock? units --------------------------------------------------

  def test_holds_live_lock_true_for_owner_with_lock_file
    Lock.acquire(@intent_dir, session: "sess-1")
    bridge = { "session" => "sess-1",
               "intent" => { "dir" => "96--demo", "store" => @store } }
    assert Bridge.holds_live_lock?(bridge)
  end

  def test_holds_live_lock_false_without_lock_file
    bridge = { "session" => "sess-1",
               "intent" => { "dir" => "96--demo", "store" => @store } }
    refute Bridge.holds_live_lock?(bridge)
  end

  def test_holds_live_lock_false_for_nil_or_blank_session
    refute Bridge.holds_live_lock?(nil)
    Lock.acquire(@intent_dir, session: "sess-1")
    refute Bridge.holds_live_lock?({ "session" => "",
                                     "intent" => { "dir" => "96--demo", "store" => @store } })
  end

  def test_intent_id_from_dir
    assert_equal "96", Bridge.intent_id_from_dir(@intent_dir)
    assert_nil Bridge.intent_id_from_dir("/tmp/no-double-dash")
  end

  # --- THE regression (intent 108 founding defect) -----------------------------

  # Intent 108 founding defect: arming ran as a one-liner subprocess whose pid
  # died instantly, so the very next tool call was denied. Session-keyed
  # ownership kills this by construction: arm in a CHILD process, then gate in
  # THIS process with the same session.
  def test_armed_via_ephemeral_subprocess_passes_the_gate_on_the_next_call
    tmp = Dir.mktmpdir("lock-gate-tmp")
    lib = File.expand_path("../scripts/lib/bridge", __dir__)
    code = "Bridge.arm_guided(%q{sess-1}, intent_id: %q{96}, " \
           "intent_dir: %q{#{@intent_dir}}, store: %q{#{@store}}, name: %q{demo})"
    # HOME is isolated too: arm's real Worktree.provision derives plastic_home
    # from HOME, and a real HOME would plant a store worktree in the LIVE
    # ~/.plastic (observed before this guard existed).
    system({ "PLASTIC_TMP" => tmp, "CLAUDE_CODE_SESSION_ID" => nil, "HOME" => @home },
           RbConfig.ruby, "-r", lib, "-e", code, exception: true)

    bridge = Bridge.read("sess-1", tmp: tmp)
    assert_nil Bridge.lock_gate_decision(bridge, @intent_file, session: "sess-1"),
               "the owner who just armed must pass the lock gate immediately"
  ensure
    FileUtils.rm_rf(tmp)
  end
end
