require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/db"

# Plastic::DB::Leases.claim_gate_reason: the second, independent write-
# authorization gate at the artifact grain (intent 111 D7; cutover intent 41
# ACTION_10). Composes UNDER the delivery-lease gate: only reached after the
# session already holds the intent's delivery lease. Returns a deny reason
# String to BLOCK, or nil to ALLOW. Dormant when no claim row exists (keeps
# AC7 green); fails open on an expired claim.
class ClaimGateTest < Minitest::Test
  def setup
    @store_home = Dir.mktmpdir("claim-gate-test-store")
    @conn = Plastic::DB.connect(@store_home)
    @t0 = Time.utc(2026, 7, 4, 12, 0, 0)
  end

  def teardown
    FileUtils.rm_rf(@store_home)
  end

  def reason(intent_id, artifact, session:, now: @t0)
    Plastic::DB::Leases.claim_gate_reason(@conn, intent_id, artifact, session: session, now: now)
  end

  def acquire(intent_id, artifact, session:, now: @t0)
    Plastic::DB::Leases.acquire(@conn, intent_id, artifact: artifact, session: session, host: "h", now: now)
  end

  def test_dormant_allows_when_no_claim
    assert_nil reason("41", "plan.md", session: "sess-a")
  end

  def test_allows_when_session_holds_fresh_claim
    acquire("41", "plan.md", session: "sess-a")
    assert_nil reason("41", "plan.md", session: "sess-a")
  end

  def test_denies_fresh_foreign_claim_and_names_holder
    acquire("41", "plan.md", session: "sess-a")
    r = reason("41", "plan.md", session: "sess-b")
    refute_nil r
    assert_includes r, "sess-a"
    assert_includes r, "plan.md"
    assert_includes r, "/plastic-lock status"
  end

  def test_denies_a_third_session_when_another_holds_it
    acquire("41", "plan.md", session: "sess-a")
    r = reason("41", "plan.md", session: "sess-c")
    refute_nil r
    assert_includes r, "sess-a"
  end

  def test_fail_open_allows_on_expired_claim
    acquire("41", "plan.md", session: "sess-a")
    later = @t0 + Plastic::DB::Leases::TTL_SECONDS + 1
    assert_nil reason("41", "plan.md", session: "sess-b", now: later)
  end

  def test_scope_isolation_across_intents
    acquire("41", "plan.md", session: "sess-a")
    assert_nil reason("52", "plan.md", session: "sess-b")
  end

  def test_scope_isolation_across_artifacts
    acquire("41", "plan.md", session: "sess-a")
    assert_nil reason("41", "spec.md", session: "sess-b")
  end

  def test_blank_artifact_is_dormant
    assert_nil reason("41", "", session: "sess-a")
    assert_nil reason("41", nil, session: "sess-a")
  end
end
