require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require_relative "../scripts/lib/bridge"

# Hermetic unit tests (intent 73c2) for Bridge.worktree_gate_decision.
#
# No real git, no real ~/.plastic: a fake $HOME tmpdir is the plastic home, the
# code worktree is a tmpdir, and the cross-intent lock scan reads bridges from an
# injected PLASTIC_TMP. Process.kill(0, $$) makes the current process a reliable
# LIVE owner; a never-allocated high pid is the reliable DEAD owner.
class WorktreeGateTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("wt-gate-home")
    @plastic_home = File.join(@home, ".plastic")
    @store = File.join(@plastic_home, "store")
    @intent_dir = File.join(@store, "73c2--worktree-enforcement-gate")
    FileUtils.mkdir_p(@intent_dir)

    @repo = Dir.mktmpdir("wt-gate-repo")
    @code_wt = File.join(@repo, ".claude", "worktrees", "73c2--worktree-enforcement-gate")
    FileUtils.mkdir_p(@code_wt)

    @tmp = Dir.mktmpdir("wt-gate-tmp")
    @saved_plastic_tmp = ENV["PLASTIC_TMP"]
    ENV["PLASTIC_TMP"] = @tmp
  end

  def teardown
    FileUtils.rm_rf(@home)
    FileUtils.rm_rf(@repo)
    FileUtils.rm_rf(@tmp)
    @saved_plastic_tmp.nil? ? ENV.delete("PLASTIC_TMP") : ENV["PLASTIC_TMP"] = @saved_plastic_tmp
  end

  # An armed, provisioned bridge owned by "me".
  def provisioned_bridge(session: "me")
    {
      "session" => session,
      "intent" => { "id" => "73c2", "dir" => "73c2--worktree-enforcement-gate", "store" => @store },
      "worktree" => {
        "code" => @code_wt,
        "code_branch" => "plastic/73c2--worktree-enforcement-gate",
        "store" => File.join(@plastic_home, ".worktrees", "73c2--worktree-enforcement-gate"),
        "store_branch" => "plastic-store/73c2--worktree-enforcement-gate",
        "provisioned" => true,
      },
      "lock" => { "owner_session" => session, "pid" => $$, "acquired_at" => nil, "host" => nil },
    }
  end

  def decision(bridge, file, session: nil)
    Bridge.worktree_gate_decision(bridge, file, home: @home, current_session: session)
  end

  # --- Rule 1: code worktree confinement -------------------------------------

  def test_blocks_code_edit_outside_the_code_worktree
    reason = decision(provisioned_bridge, File.join(@repo, "lib", "app.rb"))
    refute_nil reason, "code edit on the shared checkout must be blocked"
    assert_includes reason, @code_wt, "the block reason must name the expected worktree"
  end

  def test_allows_code_edit_inside_the_code_worktree
    assert_nil decision(provisioned_bridge, File.join(@code_wt, "lib", "app.rb"))
  end

  def test_allows_when_provisioned_false_fail_open
    bridge = provisioned_bridge
    bridge["worktree"]["provisioned"] = false
    assert_nil decision(bridge, File.join(@repo, "lib", "app.rb")),
               "non-git / global-only intents fail open"
  end

  def test_fails_open_when_no_worktree_block
    bridge = provisioned_bridge
    bridge.delete("worktree")
    assert_nil decision(bridge, File.join(@repo, "lib", "app.rb"))
  end

  def test_allows_edit_under_plastic_home_even_when_provisioned
    assert_nil decision(provisioned_bridge, File.join(@plastic_home, "store", "INDEX.md"))
  end

  def test_allows_edit_inside_own_intent_dir_even_when_provisioned
    assert_nil decision(provisioned_bridge, File.join(@intent_dir, "plan.md"))
  end

  # --- Rule 2: non-owner edit to another intent's locked store dir ------------

  # Write a bridge into PLASTIC_TMP for another intent with the given pid/session.
  def write_other_bridge(id:, store:, session:, pid:)
    File.write(
      File.join(@tmp, "plastic-#{session}.json"),
      JSON.generate(
        "session" => session,
        "intent" => { "id" => id, "store" => store },
        "build" => { "auto" => true },
        "lock" => { "owner_session" => session, "pid" => pid },
      ),
    )
  end

  def other_intent_dir(id, slug)
    d = File.join(@store, "#{id}--#{slug}")
    FileUtils.mkdir_p(d)
    d
  end

  def test_blocks_non_owner_edit_to_locked_active_intent_store
    other = other_intent_dir("99", "other-thing")
    write_other_bridge(id: "99", store: @store, session: "owner99", pid: $$) # live owner
    # An unprovisioned bridge for "me": rule 1 is inert, rule 2 fires.
    bridge = provisioned_bridge(session: "me")
    bridge["worktree"]["provisioned"] = false
    reason = decision(bridge, File.join(other, "spec.md"), session: "me")
    refute_nil reason, "editing another live-locked intent must be blocked"
    assert_includes reason, "99"
  end

  def test_allows_owner_edit_to_own_locked_intent_store
    # The other bridge is owned by the SAME session doing the edit -> not "other".
    other = other_intent_dir("99", "other-thing")
    write_other_bridge(id: "99", store: @store, session: "me", pid: $$)
    bridge = provisioned_bridge(session: "me")
    bridge["worktree"]["provisioned"] = false
    assert_nil decision(bridge, File.join(other, "spec.md"), session: "me")
  end

  def test_allows_edit_to_intent_store_with_dead_owner
    other = other_intent_dir("99", "other-thing")
    write_other_bridge(id: "99", store: @store, session: "owner99", pid: 2_147_483_000) # dead
    bridge = provisioned_bridge(session: "me")
    bridge["worktree"]["provisioned"] = false
    assert_nil decision(bridge, File.join(other, "spec.md"), session: "me"),
               "a dead owner does not hold the lock (stale reclaim)"
  end

  def test_allows_edit_under_plastic_home_outside_any_intent_dir
    # A file directly under ~/.plastic/store but not inside an {id}--{slug} dir.
    assert_nil decision(provisioned_bridge, File.join(@store, "INDEX.md"))
  end
end
