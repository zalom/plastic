require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "time"

require_relative "../scripts/lib/db"
require_relative "../scripts/lib/db/leases"

# Hermetic unit tests for Plastic::DB::Leases (intent 41, ACTION_3): lock_leases
# take/renew/release/takeover, delivery + artifact grain isolation, gate-reason
# helpers, and fail-open on a nil conn. Dir.mktmpdir store, injected now:/ttl:.
# The forked ~100-writer contention smoke test (AC2) lives in a separate file
# on purpose (test/db_contention_smoke_test.rb): it is the one sanctioned
# exception to single-process hermeticity, this file is not it.
class DbLeasesTest < Minitest::Test
  def setup
    @store_home = Dir.mktmpdir("plastic-db-leases-store")
    @conn = Plastic::DB.connect(@store_home)
  end

  def teardown
    FileUtils.rm_rf(@store_home)
  end

  def test_acquire_creates_one_live_row
    status, row = Plastic::DB::Leases.acquire(@conn, "41", session: "s-a", host: "h-a", now: t(0))

    assert_equal :acquired, status
    assert_equal "41", row["intent_id"]
    assert_nil row["artifact"]
    assert_equal "s-a", row["owner_session"]
    assert_nil row["released_at"]
  end

  def test_second_acquire_same_session_is_owned_idempotent
    Plastic::DB::Leases.acquire(@conn, "41", session: "s-a", host: "h-a", ttl: 60, now: t(0))
    status, row = Plastic::DB::Leases.acquire(@conn, "41", session: "s-a", host: "h-a", ttl: 60, now: t(10))

    assert_equal :owned, status
    assert_equal "s-a", row["owner_session"]
    assert_equal iso(t(10) + 60), row["expires_at"]
  end

  def test_second_acquire_foreign_fresh_is_held_naming_holder
    Plastic::DB::Leases.acquire(@conn, "41", session: "s-a", host: "h-a", ttl: 60, now: t(0))
    status, row = Plastic::DB::Leases.acquire(@conn, "41", session: "s-b", host: "h-b", now: t(10))

    assert_equal :held, status
    assert_equal "s-a", row["owner_session"]
  end

  def test_second_acquire_foreign_expired_is_stale
    Plastic::DB::Leases.acquire(@conn, "41", session: "s-a", host: "h-a", ttl: 60, now: t(0))
    status, row = Plastic::DB::Leases.acquire(@conn, "41", session: "s-b", host: "h-b", now: t(120))

    assert_equal :stale, status
    assert_equal "s-a", row["owner_session"]
  end

  def test_atomic_single_holder
    first_status, = Plastic::DB::Leases.acquire(@conn, "41", session: "s-a", host: "h-a", now: t(0))
    second_status, second_row = Plastic::DB::Leases.acquire(@conn, "41", session: "s-b", host: "h-b", now: t(1))

    assert_equal :acquired, first_status
    assert_equal :held, second_status
    assert_equal "s-a", second_row["owner_session"]

    live = @conn.execute(
      "SELECT COUNT(*) FROM lock_leases WHERE intent_id = ? AND artifact IS NULL AND released_at IS NULL",
      ["41"]
    ).first.first
    assert_equal 1, live
  end

  def test_artifact_claim_isolated_from_delivery_grain_and_other_artifacts
    Plastic::DB::Leases.acquire(@conn, "41", artifact: "plan.md", session: "s-a", host: "h-a", now: t(0))

    delivery_status, = Plastic::DB::Leases.acquire(@conn, "41", session: "s-b", host: "h-b", now: t(0))
    other_artifact_status, = Plastic::DB::Leases.acquire(@conn, "41", artifact: "spec.md", session: "s-b", host: "h-b", now: t(0))

    assert_equal :acquired, delivery_status
    assert_equal :acquired, other_artifact_status
  end

  def test_lease_isolated_across_intents
    Plastic::DB::Leases.acquire(@conn, "41", session: "s-a", host: "h-a", now: t(0))
    status, = Plastic::DB::Leases.acquire(@conn, "42", session: "s-b", host: "h-b", now: t(0))

    assert_equal :acquired, status
  end

  def test_renew_bumps_expires_at_only_inside_window
    Plastic::DB::Leases.acquire(@conn, "41", session: "s-a", host: "h-a", ttl: 1000, now: t(0))

    too_early = Plastic::DB::Leases.renew(@conn, "41", session: "s-a", ttl: 1000, renew_window: 100, now: t(0))
    assert_equal :not_due, too_early
    assert_equal iso(t(0) + 1000), live_row("41")["expires_at"]

    due = Plastic::DB::Leases.renew(@conn, "41", session: "s-a", ttl: 1000, renew_window: 100, now: t(950))
    assert_equal :renewed, due
    assert_equal iso(t(950) + 1000), live_row("41")["expires_at"]
  end

  def test_renew_not_owner_and_none
    assert_equal :none, Plastic::DB::Leases.renew(@conn, "41", session: "s-a", now: t(0))

    Plastic::DB::Leases.acquire(@conn, "41", session: "s-a", host: "h-a", ttl: 60, now: t(0))
    assert_equal :not_owner, Plastic::DB::Leases.renew(@conn, "41", session: "s-b", now: t(1))
  end

  def test_release_sets_released_at_and_lets_new_acquire_succeed
    Plastic::DB::Leases.acquire(@conn, "41", session: "s-a", host: "h-a", now: t(0))
    status = Plastic::DB::Leases.release(@conn, "41", session: "s-a", now: t(1))
    assert_equal :released, status

    refute_nil live_row("41", include_released: true)["released_at"]

    reacquire_status, = Plastic::DB::Leases.acquire(@conn, "41", session: "s-b", host: "h-b", now: t(2))
    assert_equal :acquired, reacquire_status
  end

  def test_release_not_owner_and_none
    assert_equal :none, Plastic::DB::Leases.release(@conn, "41", session: "s-a", now: t(0))

    Plastic::DB::Leases.acquire(@conn, "41", session: "s-a", host: "h-a", now: t(0))
    assert_equal :not_owner, Plastic::DB::Leases.release(@conn, "41", session: "s-b", now: t(1))
  end

  def test_takeover_replaces_expired_or_absent_never_fresh_foreign
    absent_status, = Plastic::DB::Leases.takeover(@conn, "41", session: "s-a", host: "h-a", now: t(0))
    assert_equal :taken, absent_status

    Plastic::DB::Leases.acquire(@conn, "42", session: "s-a", host: "h-a", ttl: 60, now: t(0))

    fresh_status, fresh_row = Plastic::DB::Leases.takeover(@conn, "42", session: "s-b", host: "h-b", now: t(10))
    assert_equal :fresh, fresh_status
    assert_equal "s-a", fresh_row["owner_session"]

    expired_status, expired_row = Plastic::DB::Leases.takeover(@conn, "42", session: "s-b", host: "h-b", now: t(120))
    assert_equal :taken, expired_status
    assert_equal "s-b", expired_row["owner_session"]

    live = @conn.execute(
      "SELECT COUNT(*) FROM lock_leases WHERE intent_id = ? AND artifact IS NULL AND released_at IS NULL",
      ["42"]
    ).first.first
    assert_equal 1, live
  end

  def test_holds_and_fresh
    refute Plastic::DB::Leases.holds?(@conn, "41", session: "s-a")

    Plastic::DB::Leases.acquire(@conn, "41", session: "s-a", host: "h-a", ttl: 60, now: t(0))
    assert Plastic::DB::Leases.holds?(@conn, "41", session: "s-a")
    refute Plastic::DB::Leases.holds?(@conn, "41", session: "s-b")

    assert Plastic::DB::Leases.fresh?(@conn, "41", now: t(1))
    refute Plastic::DB::Leases.fresh?(@conn, "41", now: t(120))
    # Stale-own still counts as holding (mirrors Lock.holds?): freshness only
    # guards against OTHER sessions.
    assert Plastic::DB::Leases.holds?(@conn, "41", session: "s-a")
  end

  def test_gate_reason_allows_holder_denies_fresh_foreign_fail_opens_expired
    assert_nil Plastic::DB::Leases.gate_reason(@conn, "41", session: "s-a", now: t(0)) # dormant

    Plastic::DB::Leases.acquire(@conn, "41", session: "s-a", host: "h-a", ttl: 60, now: t(0))
    assert_nil Plastic::DB::Leases.gate_reason(@conn, "41", session: "s-a", now: t(1)) # you hold it

    reason = Plastic::DB::Leases.gate_reason(@conn, "41", session: "s-b", now: t(1))
    refute_nil reason
    assert_match(/s-a/, reason)

    assert_nil Plastic::DB::Leases.gate_reason(@conn, "41", session: "s-b", now: t(120)) # expired: fail-open
  end

  def test_claim_gate_reason_allows_holder_denies_fresh_foreign_fail_opens_expired
    assert_nil Plastic::DB::Leases.claim_gate_reason(@conn, "41", "plan.md", session: "s-a", now: t(0))

    Plastic::DB::Leases.acquire(@conn, "41", artifact: "plan.md", session: "s-a", host: "h-a", ttl: 60, now: t(0))
    assert_nil Plastic::DB::Leases.claim_gate_reason(@conn, "41", "plan.md", session: "s-a", now: t(1))

    reason = Plastic::DB::Leases.claim_gate_reason(@conn, "41", "plan.md", session: "s-b", now: t(1))
    refute_nil reason
    assert_match(/s-a/, reason)

    assert_nil Plastic::DB::Leases.claim_gate_reason(@conn, "41", "plan.md", session: "s-b", now: t(120))
  end

  def test_fail_open_when_conn_nil
    assert_equal [:fail_open, nil], Plastic::DB::Leases.acquire(nil, "41", session: "s-a", host: "h-a")
    assert_equal [:fail_open, nil], Plastic::DB::Leases.takeover(nil, "41", session: "s-a", host: "h-a")
    assert_equal :fail_open, Plastic::DB::Leases.renew(nil, "41", session: "s-a")
    assert_equal :fail_open, Plastic::DB::Leases.release(nil, "41", session: "s-a")
    refute Plastic::DB::Leases.holds?(nil, "41", session: "s-a")
    refute Plastic::DB::Leases.fresh?(nil, "41")
    assert_nil Plastic::DB::Leases.gate_reason(nil, "41", session: "s-a")
    assert_nil Plastic::DB::Leases.claim_gate_reason(nil, "41", "plan.md", session: "s-a")
  end

  private

  def t(seconds)
    Time.utc(2026, 7, 9, 0, 0, 0) + seconds
  end

  def iso(time)
    time.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
  end

  def live_row(intent_id, include_released: false)
    sql = "SELECT * FROM lock_leases WHERE intent_id = ? AND artifact IS NULL"
    sql += " AND released_at IS NULL" unless include_released
    sql += " ORDER BY id DESC LIMIT 1"
    row = @conn.execute(sql, [intent_id]).first
    return nil unless row

    columns = %w[id intent_id artifact owner_session host acquired_at expires_at released_at created_at updated_at]
    columns.zip(row).to_h
  end
end
