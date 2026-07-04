require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/lock"

# Claim: the per-artifact claim-token layer (intent 111, D1/D3/D4/D6) that sits
# BENEATH the session-keyed delivery lock. Pure-module tests: explicit paths,
# injected now:/ttl:, no ENV, no processes.
class ClaimTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("claim-test-intent")
    @t0 = Time.utc(2026, 7, 4, 12, 0, 0)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  # --- schema + acquire (ACTION_1) --------------------------------------------

  def test_acquire_creates_claim_file_with_schema
    status, data = Claim.acquire_claim(@dir, "plan.md", session: "sess-a", now: @t0)
    assert_equal :acquired, status
    assert File.exist?(File.join(@dir, ".claims", "plan.md.claim"))
    assert_equal "plan.md", data["artifact"]
    assert_equal "sess-a", data["owner_session"]
    assert_equal @t0.utc.iso8601, data["acquired_at"]
  end

  def test_acquire_creates_claim_file_with_delegate
    _status, data = Claim.acquire_claim(@dir, "plan.md", session: "sess-a",
                                        delegate: "sub-1", now: @t0)
    assert_equal "sub-1", data["delegate"]
  end

  def test_second_acquire_same_session_is_held_and_names_holder
    Claim.acquire_claim(@dir, "plan.md", session: "sess-a", now: @t0)
    status, existing = Claim.acquire_claim(@dir, "plan.md", session: "sess-a", now: @t0)
    assert_equal :held, status
    assert_equal "sess-a", existing["owner_session"],
                 "fresh claims are never re-granted, even to the same session"
  end

  def test_second_acquire_other_session_is_held
    Claim.acquire_claim(@dir, "plan.md", session: "sess-a", now: @t0)
    status, existing = Claim.acquire_claim(@dir, "plan.md", session: "sess-b", now: @t0)
    assert_equal :held, status
    assert_equal "sess-a", existing["owner_session"]
  end

  def test_acquire_against_stale_claim_returns_stale
    Claim.acquire_claim(@dir, "plan.md", session: "sess-a", now: @t0)
    force_mtime("plan.md", @t0)
    status, existing = Claim.acquire_claim(@dir, "plan.md", session: "sess-b",
                                           now: @t0 + Lock::TTL_SECONDS + 1)
    assert_equal :stale, status
    assert_equal "sess-a", existing["owner_session"]
  end

  def test_acquire_on_corrupt_claim_returns_corrupt
    FileUtils.mkdir_p(File.join(@dir, ".claims"))
    File.write(File.join(@dir, ".claims", "plan.md.claim"), "{ not json")
    status, data = Claim.acquire_claim(@dir, "plan.md", session: "sess-a", now: @t0)
    assert_equal :corrupt, status
    assert_nil data
  end

  def test_acquire_rejects_blank_session_or_artifact
    assert_raises(ArgumentError) { Claim.acquire_claim(@dir, "plan.md", session: "  ") }
    assert_raises(ArgumentError) { Claim.acquire_claim(@dir, "", session: "sess-a") }
  end

  # --- holds / release / heartbeat (ACTION_1) ---------------------------------

  def test_holds_claim
    Claim.acquire_claim(@dir, "plan.md", session: "sess-a", now: @t0)
    assert Claim.holds_claim?(@dir, "plan.md", session: "sess-a")
    refute Claim.holds_claim?(@dir, "plan.md", session: "sess-b")
  end

  def test_holds_claim_true_even_when_stale_for_the_owner
    Claim.acquire_claim(@dir, "plan.md", session: "sess-a", now: @t0)
    force_mtime("plan.md", @t0)
    assert Claim.holds_claim?(@dir, "plan.md", session: "sess-a"),
           "stale-own still counts as holding, mirroring Lock.holds?"
  end

  def test_release_claim_deletes_file
    Claim.acquire_claim(@dir, "plan.md", session: "sess-a", now: @t0)
    assert_equal :released, Claim.release_claim(@dir, "plan.md", session: "sess-a")
    refute File.exist?(File.join(@dir, ".claims", "plan.md.claim"))
  end

  def test_release_claim_none_when_absent
    assert_equal :none, Claim.release_claim(@dir, "plan.md", session: "sess-a")
  end

  def test_release_claim_not_owner_without_force
    Claim.acquire_claim(@dir, "plan.md", session: "sess-a", now: @t0)
    assert_equal :not_owner, Claim.release_claim(@dir, "plan.md", session: "sess-b")
    assert File.exist?(File.join(@dir, ".claims", "plan.md.claim"))
  end

  def test_release_claim_force_deletes_regardless_of_owner
    Claim.acquire_claim(@dir, "plan.md", session: "sess-a", now: @t0)
    assert_equal :released,
                 Claim.release_claim(@dir, "plan.md", session: "sess-b", force: true)
    refute File.exist?(File.join(@dir, ".claims", "plan.md.claim"))
  end

  def test_heartbeat_touches_mtime
    Claim.acquire_claim(@dir, "plan.md", session: "sess-a", now: @t0)
    force_mtime("plan.md", @t0)
    t1 = @t0 + 100
    assert Claim.heartbeat(@dir, "plan.md", session: "sess-a", now: t1)
    assert_equal t1, File.mtime(File.join(@dir, ".claims", "plan.md.claim"))
  end

  def test_heartbeat_false_when_session_does_not_hold
    Claim.acquire_claim(@dir, "plan.md", session: "sess-a", now: @t0)
    force_mtime("plan.md", @t0)
    refute Claim.heartbeat(@dir, "plan.md", session: "sess-b", now: @t0 + 100)
    assert_equal @t0, File.mtime(File.join(@dir, ".claims", "plan.md.claim"))
  end

  # --- scope (ACTION_1, AC4) ----------------------------------------------------

  def test_scope_is_per_intent_per_artifact
    Claim.acquire_claim(@dir, "plan.md", session: "sess-a", now: @t0)

    # different artifact, same intent dir: unaffected.
    refute Claim.holds_claim?(@dir, "spec.md", session: "sess-a")
    status, _ = Claim.acquire_claim(@dir, "spec.md", session: "sess-b", now: @t0)
    assert_equal :acquired, status

    # different intent dir, same artifact name: unaffected.
    other_dir = Dir.mktmpdir("claim-test-intent-other")
    begin
      refute Claim.holds_claim?(other_dir, "plan.md", session: "sess-a")
      status2, _ = Claim.acquire_claim(other_dir, "plan.md", session: "sess-b", now: @t0)
      assert_equal :acquired, status2
      assert_equal "sess-a", Claim.read(@dir, "plan.md")["owner_session"]
      assert_equal "sess-b", Claim.read(other_dir, "plan.md")["owner_session"]
    ensure
      FileUtils.rm_rf(other_dir)
    end
  end

  # --- fail-open contract (ACTION_2, D6/AC6) ------------------------------------

  def test_fail_open_true_on_stale_claim
    Claim.acquire_claim(@dir, "plan.md", session: "sess-a", now: @t0)
    force_mtime("plan.md", @t0)
    assert Claim.fail_open?(@dir, "plan.md", now: @t0 + Lock::TTL_SECONDS + 1)
  end

  def test_fail_open_true_on_corrupt_claim
    FileUtils.mkdir_p(File.join(@dir, ".claims"))
    File.write(File.join(@dir, ".claims", "plan.md.claim"), "{ nope")
    assert Claim.fail_open?(@dir, "plan.md", now: @t0)
  end

  def test_fail_open_false_on_fresh_claim
    Claim.acquire_claim(@dir, "plan.md", session: "sess-a", now: @t0)
    refute Claim.fail_open?(@dir, "plan.md", now: @t0)
  end

  def test_fail_open_false_when_no_claim
    refute Claim.fail_open?(@dir, "plan.md", now: @t0)
  end

  # --- status data (ACTION_2, AC5) ----------------------------------------------

  def test_claims_status_lists_live_claims
    Claim.acquire_claim(@dir, "plan.md", session: "sess-a", now: @t0)
    Claim.acquire_claim(@dir, "spec.md", session: "sess-b", now: @t0)
    list = Claim.claims_status(@dir, now: @t0)
    assert_equal 2, list.length
    plan = list.find { |c| c["artifact"] == "plan.md" }
    spec = list.find { |c| c["artifact"] == "spec.md" }
    assert_equal "sess-a", plan["owner_session"]
    assert_equal true, plan["fresh"]
    assert_equal "sess-b", spec["owner_session"]
    assert_equal true, spec["fresh"]
  end

  def test_claims_status_marks_stale
    Claim.acquire_claim(@dir, "plan.md", session: "sess-a", now: @t0)
    force_mtime("plan.md", @t0)
    list = Claim.claims_status(@dir, now: @t0 + Lock::TTL_SECONDS + 1)
    assert_equal false, list.first["fresh"]
  end

  def test_claims_status_empty_when_no_claims_dir
    assert_equal [], Claim.claims_status(@dir, now: @t0)
  end

  private

  def force_mtime(artifact, time)
    FileUtils.touch(File.join(@dir, ".claims", "#{artifact}.claim"), mtime: time)
  end
end
