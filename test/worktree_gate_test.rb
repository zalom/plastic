require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require_relative "../scripts/lib/bridge"
require_relative "../scripts/lib/db"

# Hermetic unit tests (intent 73c2, rewired in 108, cutover intent 41
# ACTION_10) for Bridge.worktree_gate_decision.
#
# No real git, no real ~/.plastic: a fake $HOME tmpdir is the plastic home and
# the code worktree is a tmpdir. Cross-intent ownership is decided by the
# durable `lock_leases` delivery-grain row in the other intent's dir: a FRESH
# foreign lease is a live owner; an EXPIRED one is a dead owner.
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
      "lock" => { "owner_session" => session, "acquired_at" => nil, "host" => nil,
                  "type" => "delivery", "delegates" => [] },
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

  # Regression (2026-07-02): the agent's own memory dir, outside any repo,
  # was denied by rule 1. Paths outside the project repo are never confined.
  def test_write_outside_the_project_repo_is_allowed
    memory_file = File.join(@home, ".claude", "projects", "x", "memory", "note.md")
    assert_nil decision(provisioned_bridge, memory_file)
  end

  def test_write_in_an_unrelated_checkout_is_allowed
    other_repo_file = File.join(@home, "code", "other-project", "app.rb")
    assert_nil decision(provisioned_bridge, other_repo_file)
  end

  def test_another_intents_worktree_in_the_same_repo_is_blocked
    foreign = File.join(@repo, ".claude", "worktrees", "999--other", "lib", "app.rb")
    refute_nil decision(provisioned_bridge, foreign),
               "a foreign intent's worktree is still inside the repo: confined"
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

  def other_intent_dir(id, slug)
    d = File.join(@store, "#{id}--#{slug}")
    FileUtils.mkdir_p(d)
    d
  end

  # Acquire a delivery lease for the intent living at `dir` (an
  # `<store_home>/store/<id>--<slug>` path): resolves store_home and intent_id
  # from the path itself, mirroring how Bridge/Worktree resolve it in
  # production.
  def acquire_lease(dir, session:, now: Time.now)
    intent_id = Bridge.intent_id_from_dir(dir)
    store_home = File.dirname(File.dirname(dir))
    conn = Plastic::DB.connect(store_home)
    Plastic::DB::Leases.acquire(conn, intent_id, session: session, host: "h", now: now)
  end

  def add_delegate(dir, delegate:, session:)
    intent_id = Bridge.intent_id_from_dir(dir)
    store_home = File.dirname(File.dirname(dir))
    conn = Plastic::DB.connect(store_home)
    Plastic::DB::Leases.add_delegate(conn, intent_id, delegate: delegate, session: session)
  end

  def test_blocks_non_owner_edit_to_locked_active_intent_store
    other = other_intent_dir("99", "other-thing")
    acquire_lease(other, session: "owner99") # fresh foreign lease = live owner
    # An unprovisioned bridge for "me": rule 1 is inert, rule 2 fires.
    bridge = provisioned_bridge(session: "me")
    bridge["worktree"]["provisioned"] = false
    reason = decision(bridge, File.join(other, "spec.md"), session: "me")
    refute_nil reason, "editing another live-locked intent must be blocked"
    assert_includes reason, "99"
  end

  def test_allows_owner_edit_to_own_locked_intent_store
    # The other intent's lease is owned by the SAME session doing the edit.
    other = other_intent_dir("99", "other-thing")
    acquire_lease(other, session: "me")
    bridge = provisioned_bridge(session: "me")
    bridge["worktree"]["provisioned"] = false
    assert_nil decision(bridge, File.join(other, "spec.md"), session: "me")
  end

  def test_allows_edit_to_intent_store_with_stale_lock
    other = other_intent_dir("99", "other-thing")
    acquire_lease(other, session: "owner99", now: Time.now - 4000) # expired = dead owner
    bridge = provisioned_bridge(session: "me")
    bridge["worktree"]["provisioned"] = false
    assert_nil decision(bridge, File.join(other, "spec.md"), session: "me"),
               "an expired lease does not hold (leases fail open on expiry)"
  end

  def test_allows_edit_under_plastic_home_outside_any_intent_dir
    # A file directly under ~/.plastic/store but not inside an {id}--{slug} dir.
    assert_nil decision(provisioned_bridge, File.join(@store, "INDEX.md"))
  end

  # --- Solo-mode detection (intent 128) --------------------------------------
  # Positive-only confirmation from the durable `lock_leases` rows relaxes
  # both rules to ALLOW when exactly one session is delivering.

  def test_solo_relaxes_rule1_code_confinement
    acquire_lease(@intent_dir, session: "me") # the ONLY fresh lease in scope
    assert_nil decision(provisioned_bridge, File.join(@repo, "lib", "app.rb")),
               "solo confirmed: rule 1 (worktree confinement) relaxes to allow"
  end

  def test_solo_does_not_relax_rule1_under_two_fresh_locks_same_owner
    acquire_lease(@intent_dir, session: "me")
    other = other_intent_dir("77", "other-parallel")
    acquire_lease(other, session: "me") # same owner, second fresh lease: PARALLEL (AC2)
    refute_nil decision(provisioned_bridge, File.join(@repo, "lib", "app.rb")),
               "two fresh leases under one owner_session is parallel-in-play, not solo"
  end

  def test_solo_does_not_relax_rule1_with_a_delegate
    acquire_lease(@intent_dir, session: "me")
    add_delegate(@intent_dir, delegate: "sub-1", session: "me")
    refute_nil decision(provisioned_bridge, File.join(@repo, "lib", "app.rb")),
               "a registered delegate is a team, not solo (AC3)"
  end

  def test_solo_does_not_relax_rule1_with_blank_session
    acquire_lease(@intent_dir, session: "me")
    bridge = provisioned_bridge(session: "")
    refute_nil decision(bridge, File.join(@repo, "lib", "app.rb")),
               "a blank session can never be positively confirmed solo (AC4)"
  end

  def test_solo_never_relaxes_rule2_across_projects_review_finding_1
    # Hardening (review finding 1): worktree-gate's scan_roots include the
    # EDIT TARGET's own store (not just the acting bridge's own store plus
    # the global store), so a live foreign lease on a DIFFERENT project's
    # intent is never invisible to the scan just because that project isn't
    # "mine". Solo can never be confirmed here, so rule 2 stays denied even
    # though the rival lives in a completely different project store.
    other_project_store = File.join(@plastic_home, "projects", "otherproj", "store")
    other = File.join(other_project_store, "99--other-thing")
    FileUtils.mkdir_p(other)
    acquire_lease(other, session: "owner99") # fresh, foreign, cross-project rival
    acquire_lease(@intent_dir, session: "me") # "me"'s own fresh lease, elsewhere
    bridge = provisioned_bridge(session: "me")
    bridge["worktree"]["provisioned"] = false
    reason = decision(bridge, File.join(other, "spec.md"), session: "me")
    refute_nil reason,
               "the target's own store is now in scan_roots: a cross-project rival still defeats solo"
  end

  def test_solo_never_relaxes_rule2_when_the_rival_lock_is_in_scanned_roots
    # The common case: the rival's store IS in solo's scan (same store as
    # "me"'s own intent), so its fresh foreign lease is itself a second fresh
    # lease in scope. Solo can never be confirmed, so rule 2 stays denied.
    other = other_intent_dir("99", "other-thing")
    acquire_lease(other, session: "owner99")
    acquire_lease(@intent_dir, session: "me")
    bridge = provisioned_bridge(session: "me")
    bridge["worktree"]["provisioned"] = false
    reason = decision(bridge, File.join(other, "spec.md"), session: "me")
    refute_nil reason, "a live rival lease in the same scanned store defeats solo by construction"
  end
end
