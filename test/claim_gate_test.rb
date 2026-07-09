require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/lock"

# Claim.claim_gate_reason: the second, independent write-authorization gate at
# the file grain (intent 111 D7). Composes UNDER the delivery-lock gate: only
# reached after the session already holds the intent's delivery lock. Returns
# a deny reason String to BLOCK, or nil to ALLOW. Dormant when no claim file
# exists (keeps AC7 green); fails open on stale/corrupt (defers to the named
# Claim.fail_open? contract).
class ClaimGateTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("claim-gate-test-intent")
    @t0 = Time.utc(2026, 7, 4, 12, 0, 0)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_dormant_allows_when_no_claim_file
    assert_nil Claim.claim_gate_reason(@dir, "plan.md", session: "sess-a", now: @t0)
  end

  def test_allows_when_session_holds_fresh_claim
    Claim.acquire_claim(@dir, "plan.md", session: "sess-a", now: @t0)
    assert_nil Claim.claim_gate_reason(@dir, "plan.md", session: "sess-a", now: @t0)
  end

  def test_denies_fresh_foreign_claim_and_names_holder
    Claim.acquire_claim(@dir, "plan.md", session: "sess-a", now: @t0)
    reason = Claim.claim_gate_reason(@dir, "plan.md", session: "sess-b", now: @t0)
    refute_nil reason
    assert_includes reason, "sess-a"
    assert_includes reason, "plan.md"
    assert_includes reason, "/plastic-doctor check the lock status"
  end

  def test_denies_same_session_when_another_holds_via_delegate
    Claim.acquire_claim(@dir, "plan.md", session: "sess-a", delegate: "d1", now: @t0)
    reason = Claim.claim_gate_reason(@dir, "plan.md", session: "sess-c", now: @t0)
    refute_nil reason
    assert_includes reason, "sess-a"
  end

  def test_fail_open_allows_on_stale_claim
    Claim.acquire_claim(@dir, "plan.md", session: "sess-a", now: @t0)
    FileUtils.touch(File.join(@dir, ".claims", "plan.md.claim"), mtime: @t0)
    later = @t0 + Lock::TTL_SECONDS + 1
    assert Claim.fail_open?(@dir, "plan.md", now: later)
    assert_nil Claim.claim_gate_reason(@dir, "plan.md", session: "sess-b", now: later)
  end

  def test_fail_open_allows_on_corrupt_claim
    FileUtils.mkdir_p(File.join(@dir, ".claims"))
    File.write(File.join(@dir, ".claims", "plan.md.claim"), "{ nope")
    assert_nil Claim.claim_gate_reason(@dir, "plan.md", session: "sess-a", now: @t0)
  end

  def test_scope_isolation_across_intents
    dir_x = Dir.mktmpdir("claim-gate-test-x")
    dir_y = Dir.mktmpdir("claim-gate-test-y")
    begin
      Claim.acquire_claim(dir_x, "plan.md", session: "sess-a", now: @t0)
      assert_nil Claim.claim_gate_reason(dir_y, "plan.md", session: "sess-b", now: @t0)
    ensure
      FileUtils.rm_rf(dir_x)
      FileUtils.rm_rf(dir_y)
    end
  end
end
