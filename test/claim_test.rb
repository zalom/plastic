require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/db"

# Claim: the per-artifact claim lease (intent 111, D1/D3/D4/D6), cut over to
# the artifact grain of `lock_leases` in intent 41 ACTION_10 (artifact IS NOT
# NULL). The core acquire/held/stale/release/gate-reason mechanics are grain-
# agnostic and already exercised by db_leases_test.rb (ACTION_3); this file
# focuses on the claim-specific contracts: exclusivity is O_EXCL-equivalent
# (never idempotently re-granted, even to the same session), delivery- and
# artifact-grain isolation, per-intent-per-artifact scope, and the AC5 status
# listing (artifact_leases_for). There is no more "corrupt claim" state (a DB
# row cannot be unparseable JSON) and no delegate concept for claims (never
# functionally exercised by any caller; see lock_test.rb for delivery-grain
# delegates, which ARE real).
class ClaimTest < Minitest::Test
  def setup
    @store_home = Dir.mktmpdir("claim-test-store")
    @conn = Plastic::DB.connect(@store_home)
    @t0 = Time.utc(2026, 7, 4, 12, 0, 0)
  end

  def teardown
    FileUtils.rm_rf(@store_home)
  end

  def acquire(artifact, session:, now: @t0)
    Plastic::DB::Leases.acquire(@conn, "41", artifact: artifact, session: session, host: "h", now: now)
  end

  # --- acquire -----------------------------------------------------------------

  def test_acquire_creates_a_live_artifact_lease
    status, data = acquire("plan.md", session: "sess-a")
    assert_equal :acquired, status
    assert_equal "plan.md", data["artifact"]
    assert_equal "sess-a", data["owner_session"]
    assert_equal @t0.utc.iso8601, data["acquired_at"]
  end

  def test_second_acquire_same_session_is_held_never_idempotent
    acquire("plan.md", session: "sess-a")
    status, existing = acquire("plan.md", session: "sess-a")
    assert_equal :held, status,
                 "fresh claims are never re-granted, even to the same session"
    assert_equal "sess-a", existing["owner_session"]
  end

  def test_second_acquire_other_session_is_held
    acquire("plan.md", session: "sess-a")
    status, existing = acquire("plan.md", session: "sess-b")
    assert_equal :held, status
    assert_equal "sess-a", existing["owner_session"]
  end

  def test_acquire_against_expired_claim_returns_stale
    acquire("plan.md", session: "sess-a")
    status, existing = Plastic::DB::Leases.acquire(
      @conn, "41", artifact: "plan.md", session: "sess-b", host: "h",
      now: @t0 + Plastic::DB::Leases::TTL_SECONDS + 1
    )
    assert_equal :stale, status
    assert_equal "sess-a", existing["owner_session"]
  end

  # --- holds / release / renew -------------------------------------------------

  def test_holds
    acquire("plan.md", session: "sess-a")
    assert Plastic::DB::Leases.holds?(@conn, "41", artifact: "plan.md", session: "sess-a")
    refute Plastic::DB::Leases.holds?(@conn, "41", artifact: "plan.md", session: "sess-b")
  end

  def test_holds_true_even_when_expired_for_the_owner
    acquire("plan.md", session: "sess-a")
    later = @t0 + Plastic::DB::Leases::TTL_SECONDS + 1
    assert Plastic::DB::Leases.holds?(@conn, "41", artifact: "plan.md", session: "sess-a"),
           "expired-own still counts as holding"
  end

  def test_release_frees_it
    acquire("plan.md", session: "sess-a")
    assert_equal :released, Plastic::DB::Leases.release(@conn, "41", artifact: "plan.md", session: "sess-a")
    refute Plastic::DB::Leases.holds?(@conn, "41", artifact: "plan.md", session: "sess-a")
  end

  def test_release_none_when_absent
    assert_equal :none, Plastic::DB::Leases.release(@conn, "41", artifact: "plan.md", session: "sess-a")
  end

  def test_release_not_owner
    acquire("plan.md", session: "sess-a")
    assert_equal :not_owner, Plastic::DB::Leases.release(@conn, "41", artifact: "plan.md", session: "sess-b")
    assert Plastic::DB::Leases.holds?(@conn, "41", artifact: "plan.md", session: "sess-a")
  end

  # --- scope (ACTION_1, AC4): per-intent-per-artifact --------------------------

  def test_scope_is_per_intent_per_artifact
    acquire("plan.md", session: "sess-a")

    # different artifact, same intent: unaffected.
    refute Plastic::DB::Leases.holds?(@conn, "41", artifact: "spec.md", session: "sess-a")
    status, = Plastic::DB::Leases.acquire(@conn, "41", artifact: "spec.md", session: "sess-b", host: "h", now: @t0)
    assert_equal :acquired, status

    # different intent, same artifact name: unaffected.
    refute Plastic::DB::Leases.holds?(@conn, "52", artifact: "plan.md", session: "sess-a")
    status2, = Plastic::DB::Leases.acquire(@conn, "52", artifact: "plan.md", session: "sess-b", host: "h", now: @t0)
    assert_equal :acquired, status2
    assert_equal "sess-a", Plastic::DB::Leases.current(@conn, "41", artifact: "plan.md")["owner_session"]
    assert_equal "sess-b", Plastic::DB::Leases.current(@conn, "52", artifact: "plan.md")["owner_session"]
  end

  def test_delivery_and_artifact_grain_are_independent
    # A delivery-grain lease (artifact: nil) on the same intent does not
    # collide with an artifact-grain claim, and vice versa.
    Plastic::DB::Leases.acquire(@conn, "41", session: "sess-a", host: "h", now: @t0)
    status, = acquire("plan.md", session: "sess-b")
    assert_equal :acquired, status
    assert_equal "sess-a", Plastic::DB::Leases.current(@conn, "41")["owner_session"]
    assert_equal "sess-b", Plastic::DB::Leases.current(@conn, "41", artifact: "plan.md")["owner_session"]
  end

  # --- claim_gate_reason's fail-open contract (D6/AC6) ------------------------

  def test_claim_gate_reason_allows_on_expired_claim
    acquire("plan.md", session: "sess-a")
    later = @t0 + Plastic::DB::Leases::TTL_SECONDS + 1
    assert_nil Plastic::DB::Leases.claim_gate_reason(@conn, "41", "plan.md", session: "sess-b", now: later)
  end

  def test_claim_gate_reason_denies_a_fresh_foreign_claim
    acquire("plan.md", session: "sess-a")
    reason = Plastic::DB::Leases.claim_gate_reason(@conn, "41", "plan.md", session: "sess-b", now: @t0)
    refute_nil reason
    assert_includes reason, "sess-a"
    assert_includes reason, "plan.md"
  end

  def test_claim_gate_reason_dormant_when_no_claim
    assert_nil Plastic::DB::Leases.claim_gate_reason(@conn, "41", "plan.md", session: "sess-a", now: @t0)
  end

  # --- status data (ACTION_2/ACTION_10, AC5) -----------------------------------

  def test_artifact_leases_for_lists_live_claims
    acquire("plan.md", session: "sess-a")
    acquire("spec.md", session: "sess-b")
    list = Plastic::DB::Leases.artifact_leases_for(@conn, "41", now: @t0)
    assert_equal 2, list.length
    plan = list.find { |c| c["artifact"] == "plan.md" }
    spec = list.find { |c| c["artifact"] == "spec.md" }
    assert_equal "sess-a", plan["owner_session"]
    assert_equal true, plan["fresh"]
    assert_equal "sess-b", spec["owner_session"]
    assert_equal true, spec["fresh"]
  end

  def test_artifact_leases_for_marks_expired
    acquire("plan.md", session: "sess-a")
    list = Plastic::DB::Leases.artifact_leases_for(@conn, "41", now: @t0 + Plastic::DB::Leases::TTL_SECONDS + 1)
    assert_equal false, list.first["fresh"]
  end

  def test_artifact_leases_for_empty_when_none
    assert_equal [], Plastic::DB::Leases.artifact_leases_for(@conn, "41")
  end
end
