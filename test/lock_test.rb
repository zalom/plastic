require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/db"

# The durable single-owner delivery lease (intent 108, D1/D2/D4; cutover
# intent 41 ACTION_10). The file-based Lock/Claim modules this file used to
# test are retired (deleted, per the "prefer deleting" instruction); their
# behavior lives in Plastic::DB::Leases now, and their core acquire/renew/
# release/takeover/gate_reason coverage is already exercised in
# db_leases_test.rb (ACTION_3). This file owns what ACTION_10 ADDED on top:
# delegates (a genuinely new column/table, since the old file schema's
# `delegates` array had no DB equivalent until now), the public `current`
# read, and `fresh_delivery_rows` (solo-delivery's aggregate read). Pure-module
# tests: explicit paths (Dir.mktmpdir store), injected now:, no ENV, no
# processes.
class LockTest < Minitest::Test
  def setup
    @store_home = Dir.mktmpdir("lease-delegates-store")
    @conn = Plastic::DB.connect(@store_home)
    @t0 = Time.utc(2026, 7, 9, 12, 0, 0)
  end

  def teardown
    FileUtils.rm_rf(@store_home)
  end

  # --- current ----------------------------------------------------------------

  def test_current_returns_the_live_row
    Plastic::DB::Leases.acquire(@conn, "41", session: "sess-a", host: "host-1", now: @t0)
    row = Plastic::DB::Leases.current(@conn, "41")
    refute_nil row
    assert_equal "sess-a", row["owner_session"]
  end

  def test_current_nil_when_no_live_row
    assert_nil Plastic::DB::Leases.current(@conn, "41")
  end

  def test_current_fails_open_on_nil_conn
    assert_nil Plastic::DB::Leases.current(nil, "41")
  end

  # --- delegates (new in this cutover; no file-schema equivalent existed) -----

  def test_owner_adds_delegate_and_delegate_is_authorized
    Plastic::DB::Leases.acquire(@conn, "41", session: "sess-a", host: "h", now: @t0)
    assert Plastic::DB::Leases.add_delegate(@conn, "41", delegate: "sub-1", session: "sess-a")
    assert Plastic::DB::Leases.authorized?(@conn, "41", session: "sub-1")
    assert Plastic::DB::Leases.authorized?(@conn, "41", session: "sess-a")
    refute Plastic::DB::Leases.authorized?(@conn, "41", session: "stranger")
  end

  def test_non_owner_cannot_delegate
    Plastic::DB::Leases.acquire(@conn, "41", session: "sess-a", host: "h", now: @t0)
    refute Plastic::DB::Leases.add_delegate(@conn, "41", delegate: "sub-1", session: "not-the-owner")
    refute Plastic::DB::Leases.authorized?(@conn, "41", session: "sub-1")
  end

  def test_add_delegate_is_idempotent
    Plastic::DB::Leases.acquire(@conn, "41", session: "sess-a", host: "h", now: @t0)
    2.times { Plastic::DB::Leases.add_delegate(@conn, "41", delegate: "sub-1", session: "sess-a") }
    row = Plastic::DB::Leases.current(@conn, "41")
    assert_equal ["sub-1"], Plastic::DB::Leases.delegates_for(@conn, row["id"])
  end

  def test_delegate_cannot_delegate_or_release
    Plastic::DB::Leases.acquire(@conn, "41", session: "sess-a", host: "h", now: @t0)
    Plastic::DB::Leases.add_delegate(@conn, "41", delegate: "sub-1", session: "sess-a")
    refute Plastic::DB::Leases.add_delegate(@conn, "41", delegate: "sub-2", session: "sub-1")
    assert_equal :not_owner, Plastic::DB::Leases.release(@conn, "41", session: "sub-1")
  end

  def test_delegates_are_scoped_to_the_current_live_row_only
    # A NEW acquire (after the old row released) starts with an empty
    # delegate set: delegates do not carry over across takeovers/re-arms,
    # mirroring the retired file schema's "new lock = new delegates array".
    Plastic::DB::Leases.acquire(@conn, "41", session: "sess-a", host: "h", now: @t0)
    Plastic::DB::Leases.add_delegate(@conn, "41", delegate: "sub-1", session: "sess-a")
    Plastic::DB::Leases.release(@conn, "41", session: "sess-a")
    Plastic::DB::Leases.acquire(@conn, "41", session: "sess-b", host: "h", now: @t0)
    refute Plastic::DB::Leases.authorized?(@conn, "41", session: "sub-1")
  end

  def test_add_delegate_rejects_blank_delegate
    Plastic::DB::Leases.acquire(@conn, "41", session: "sess-a", host: "h", now: @t0)
    refute Plastic::DB::Leases.add_delegate(@conn, "41", delegate: "", session: "sess-a")
    refute Plastic::DB::Leases.add_delegate(@conn, "41", delegate: nil, session: "sess-a")
  end

  # --- fresh_delivery_rows (solo-delivery's aggregate read) -------------------

  def test_fresh_delivery_rows_lists_every_live_unexpired_delivery_lease
    Plastic::DB::Leases.acquire(@conn, "41", session: "sess-a", host: "h", now: @t0)
    Plastic::DB::Leases.acquire(@conn, "52", session: "sess-b", host: "h", now: @t0)
    rows = Plastic::DB::Leases.fresh_delivery_rows(@conn, now: @t0)
    assert_equal 2, rows.length
    assert_equal %w[sess-a sess-b].sort, rows.map { |r| r["owner_session"] }.sort
  end

  def test_fresh_delivery_rows_excludes_expired
    Plastic::DB::Leases.acquire(@conn, "41", session: "sess-a", host: "h", now: @t0)
    later = @t0 + Plastic::DB::Leases::TTL_SECONDS + 1
    rows = Plastic::DB::Leases.fresh_delivery_rows(@conn, now: later)
    assert_empty rows
  end

  def test_fresh_delivery_rows_excludes_artifact_grain
    Plastic::DB::Leases.acquire(@conn, "41", artifact: "plan.md", session: "sess-a", host: "h", now: @t0)
    assert_empty Plastic::DB::Leases.fresh_delivery_rows(@conn, now: @t0)
  end

  def test_fresh_delivery_rows_excludes_released
    Plastic::DB::Leases.acquire(@conn, "41", session: "sess-a", host: "h", now: @t0)
    Plastic::DB::Leases.release(@conn, "41", session: "sess-a", now: @t0)
    assert_empty Plastic::DB::Leases.fresh_delivery_rows(@conn, now: @t0)
  end

  def test_fresh_delivery_rows_fails_open_on_nil_conn
    assert_equal [], Plastic::DB::Leases.fresh_delivery_rows(nil)
  end

  # --- artifact_leases_for (plastic-lock status's claim listing) --------------

  def test_artifact_leases_for_lists_live_claims
    Plastic::DB::Leases.acquire(@conn, "41", artifact: "plan.md", session: "sess-a", host: "h", now: @t0)
    Plastic::DB::Leases.acquire(@conn, "41", artifact: "spec.md", session: "sess-b", host: "h", now: @t0)
    list = Plastic::DB::Leases.artifact_leases_for(@conn, "41", now: @t0)
    assert_equal 2, list.length
    plan = list.find { |c| c["artifact"] == "plan.md" }
    assert_equal "sess-a", plan["owner_session"]
    assert_equal true, plan["fresh"]
  end

  def test_artifact_leases_for_marks_expired
    Plastic::DB::Leases.acquire(@conn, "41", artifact: "plan.md", session: "sess-a", host: "h", now: @t0)
    later = @t0 + Plastic::DB::Leases::TTL_SECONDS + 1
    list = Plastic::DB::Leases.artifact_leases_for(@conn, "41", now: later)
    assert_equal false, list.first["fresh"]
  end

  def test_artifact_leases_for_empty_when_none
    assert_equal [], Plastic::DB::Leases.artifact_leases_for(@conn, "41")
  end

  def test_artifact_leases_for_fails_open_on_nil_conn
    assert_equal [], Plastic::DB::Leases.artifact_leases_for(nil, "41")
  end
end
