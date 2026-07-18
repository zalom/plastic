require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/lock"

# The durable single-owner delivery lock (intent 108, D1/D2/D3/D4).
# Pure-module tests: explicit paths, injected now:/ttl:, no ENV, no processes.
class LockTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("lock-test-intent")
    @t0 = Time.utc(2026, 7, 2, 12, 0, 0)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  # --- schema + acquire ------------------------------------------------------

  def test_acquire_creates_delivery_lock_with_schema
    status, data = Lock.acquire(@dir, session: "sess-a", host: "host-1", now: @t0,
                                harness: "codex", agent: "implementer", model: "gpt-5",
                                thread: "thread-a", run_mode: "auto")
    assert_equal :acquired, status
    assert File.exist?(File.join(@dir, "delivery.lock"))
    assert_equal "delivery", data["type"]
    assert_equal "sess-a", data["owner_session"]
    assert_equal "host-1", data["host"]
    assert_equal @t0.utc.iso8601, data["acquired_at"]
    assert_equal [], data["delegates"]
    assert_equal "codex", data["owner_harness"]
    assert_equal "implementer", data["owner_agent"]
    assert_equal "gpt-5", data["owner_model"]
    assert_equal "thread-a", data["owner_thread"]
    assert_equal "auto", data["run_mode"]
    assert_equal [], data["delegate_activity"]
    refute data.key?("pid"), "no pid anywhere in the lock schema (D1)"
  end

  def test_same_owner_rearm_preserves_nonblank_provenance_delegates_and_activity
    Lock.acquire(@dir, session: "sess-a", now: @t0, harness: "codex", agent: "owner")
    Lock.add_delegate(@dir, delegate: "sub-1", session: "sess-a", now: @t0 + 1,
                      harness: "codex", agent: "worker")
    status, data = Lock.acquire(@dir, session: "sess-a", now: @t0 + 2,
                                harness: "", agent: "new-owner", model: "gpt-5")
    assert_equal :owned, status
    assert_equal "codex", data["owner_harness"]
    assert_equal "new-owner", data["owner_agent"]
    assert_equal "gpt-5", data["owner_model"]
    assert_equal ["sub-1"], data["delegates"]
    assert_equal 1, data["delegate_activity"].length
  end

  def test_legacy_lock_rearms_without_requiring_provenance
    File.write(File.join(@dir, "delivery.lock"), JSON.generate(
      "type" => "delivery", "owner_session" => "sess-a", "delegates" => ["sub-1"]
    ))
    status, data = Lock.acquire(@dir, session: "sess-a", now: @t0)
    assert_equal :owned, status
    assert_equal ["sub-1"], data["delegates"]
    assert_nil data["owner_harness"]
  end

  def test_acquire_is_idempotent_for_the_owner
    Lock.acquire(@dir, session: "sess-a", now: @t0)
    status, data = Lock.acquire(@dir, session: "sess-a", now: @t0 + 10)
    assert_equal :owned, status
    assert_equal "sess-a", data["owner_session"]
  end

  def test_acquire_refuses_a_fresh_foreign_lock
    Lock.acquire(@dir, session: "sess-a", now: @t0)
    status, data = Lock.acquire(@dir, session: "sess-b", now: @t0, ttl: 1800)
    assert_equal :held, status
    assert_equal "sess-a", data["owner_session"]
  end

  def test_acquire_reports_stale_never_silently_reclaims
    Lock.acquire(@dir, session: "sess-a", now: @t0)
    force_mtime(@t0)
    status, _ = Lock.acquire(@dir, session: "sess-b", ttl: 1800, now: @t0 + 3600)
    assert_equal :stale, status
    assert_equal "sess-a", Lock.read(@dir)["owner_session"],
                 "acquire must never take over a stale lock; takeover is explicit"
  end

  def test_acquire_rejects_blank_session_and_unknown_type
    assert_raises(ArgumentError) { Lock.acquire(@dir, session: "  ") }
    assert_raises(ArgumentError) { Lock.acquire(@dir, session: "s", type: "banana") }
  end

  def test_corrupt_lock_is_detected_and_reported
    File.write(File.join(@dir, "delivery.lock"), "{ not json")
    assert Lock.corrupt?(@dir)
    status, _ = Lock.acquire(@dir, session: "sess-a", now: @t0)
    assert_equal :corrupt, status
  end

  # --- mutual-exclusion seam (D3) --------------------------------------------

  def test_delivery_acquire_is_excluded_by_a_fresh_maintenance_lock
    Lock.acquire(@dir, session: "curator", type: "maintenance", now: @t0)
    status, other = Lock.acquire(@dir, session: "sess-a", type: "delivery", now: @t0)
    assert_equal :excluded, status
    assert_equal "maintenance", other["type"]
  end

  def test_maintenance_acquire_is_excluded_by_a_fresh_delivery_lock
    Lock.acquire(@dir, session: "sess-a", type: "delivery", now: @t0)
    status, _ = Lock.acquire(@dir, session: "curator", type: "maintenance", now: @t0)
    assert_equal :excluded, status
  end

  # --- lease -------------------------------------------------------------------

  def test_fresh_within_ttl_stale_after
    Lock.acquire(@dir, session: "sess-a", now: @t0)
    force_mtime(@t0)
    assert Lock.fresh?(@dir, ttl: 1800, now: @t0 + 1799)
    refute Lock.fresh?(@dir, ttl: 1800, now: @t0 + 1801)
  end

  def test_heartbeat_touches_mtime_for_owner_only
    Lock.acquire(@dir, session: "sess-a", now: @t0)
    force_mtime(@t0)
    refute Lock.heartbeat(@dir, session: "sess-b", now: @t0 + 100)
    assert_equal @t0, File.mtime(File.join(@dir, "delivery.lock"))
    assert Lock.heartbeat(@dir, session: "sess-a", now: @t0 + 100)
    assert_equal @t0 + 100, File.mtime(File.join(@dir, "delivery.lock"))
    assert_equal [], Lock.read(@dir)["delegate_activity"], "heartbeat must not rewrite payload"
  end

  # --- delegation (D4) --------------------------------------------------------

  def test_owner_adds_delegate_and_delegate_holds
    Lock.acquire(@dir, session: "sess-a", now: @t0)
    assert Lock.add_delegate(@dir, delegate: "sub-1", session: "sess-a")
    assert Lock.holds?(@dir, session: "sub-1")
    assert Lock.holds?(@dir, session: "sess-a")
    refute Lock.holds?(@dir, session: "stranger")
  end

  def test_delegate_provenance_and_status_transitions_do_not_change_authorization
    Lock.acquire(@dir, session: "sess-a", now: @t0)
    assert Lock.add_delegate(@dir, delegate: "sub-1", session: "sess-a", now: @t0 + 1,
                             harness: "codex", agent: "executor", model: "gpt-5",
                             thread: "thread-1")
    activity = Lock.read(@dir)["delegate_activity"].last
    assert_equal "active", activity["status"]
    assert_equal "codex", activity["harness"]
    assert_equal (@t0 + 1).utc.iso8601, activity["registered_at"]
    assert Lock.update_delegate_status(@dir, delegate: "sub-1", status: "finished",
                                       session: "sess-a", now: @t0 + 2)
    assert Lock.holds?(@dir, session: "sub-1"), "activity status is not authorization"
    activity = Lock.read(@dir)["delegate_activity"].last
    assert_equal "finished", activity["status"]
    assert_equal (@t0 + 2).utc.iso8601, activity["last_activity_at"]
    refute Lock.update_delegate_status(@dir, delegate: "sub-1", status: "active",
                                       session: "sess-a", now: @t0 + 3)
    refute Lock.update_delegate_status(@dir, delegate: "sub-1", status: "failed",
                                       session: "sub-1", now: @t0 + 3)
  end

  def test_delegate_activity_is_upserted_and_bounded
    Lock.acquire(@dir, session: "sess-a", now: @t0)
    21.times do |i|
      Lock.add_delegate(@dir, delegate: "sub-#{i}", session: "sess-a", now: @t0 + i)
      Lock.update_delegate_status(@dir, delegate: "sub-#{i}", status: "finished",
                                  session: "sess-a", now: @t0 + i + 0.5)
    end
    activity = Lock.read(@dir)["delegate_activity"]
    assert_equal Lock::DELEGATE_ACTIVITY_LIMIT, activity.length
    assert_equal "sub-1", activity.first["session"]
    Lock.add_delegate(@dir, delegate: "sub-10", session: "sess-a", now: @t0 + 30,
                      agent: "updated")
    activity = Lock.read(@dir)["delegate_activity"]
    assert_equal 20, activity.length
    assert_equal 1, activity.count { |record| record["session"] == "sub-10" }
    assert_equal "updated", activity.last["agent"]
  end

  def test_terminal_history_never_evicts_an_older_active_delegate
    Lock.acquire(@dir, session: "sess-a", now: @t0)
    Lock.add_delegate(@dir, delegate: "active-old", session: "sess-a", now: @t0 + 1,
                      harness: "codex", agent: "active-agent")
    21.times do |i|
      session = "terminal-#{i}"
      Lock.add_delegate(@dir, delegate: session, session: "sess-a", now: @t0 + i + 2,
                        harness: "codex", agent: "terminal-agent")
      Lock.update_delegate_status(@dir, delegate: session, status: "finished",
                                  session: "sess-a", now: @t0 + i + 2.5)
    end

    activity = Lock.read(@dir)["delegate_activity"]
    assert_equal 1, activity.count { |record| record["status"] == "active" }
    assert_equal Lock::DELEGATE_ACTIVITY_LIMIT,
                 activity.count { |record| record["status"] != "active" }
    assert_equal "active-old", Lock.who(@dir, now: @t0 + 30)["delegates"].last["session"]
  end

  def test_delegate_cannot_re_delegate_or_release
    Lock.acquire(@dir, session: "sess-a", now: @t0)
    Lock.add_delegate(@dir, delegate: "sub-1", session: "sess-a")
    refute Lock.add_delegate(@dir, delegate: "sub-2", session: "sub-1")
    assert_equal :not_owner, Lock.release(@dir, session: "sub-1")
  end

  # --- release + takeover -----------------------------------------------------

  def test_owner_release_deletes_the_file
    Lock.acquire(@dir, session: "sess-a", now: @t0)
    assert_equal :released, Lock.release(@dir, session: "sess-a")
    refute File.exist?(File.join(@dir, "delivery.lock"))
    assert_equal :none, Lock.release(@dir, session: "sess-a")
  end

  def test_takeover_refuses_a_fresh_foreign_lock
    Lock.acquire(@dir, session: "sess-a", now: @t0)
    status, _ = Lock.takeover(@dir, session: "sess-b", ttl: 1800, now: @t0 + 10)
    assert_equal :fresh, status
    assert_equal "sess-a", Lock.read(@dir)["owner_session"]
  end

  def test_takeover_replaces_a_stale_lock_and_appends_a_savepoint_audit_line
    Lock.acquire(@dir, session: "sess-a", now: @t0)
    force_mtime(@t0)
    status, data = Lock.takeover(@dir, session: "sess-b", ttl: 1800, now: @t0 + 3600)
    assert_equal :taken, status
    assert_equal "sess-b", data["owner_session"]
    audit = File.read(File.join(@dir, "savepoint.md"))
    assert_includes audit, "Lock  takeover: sess-b reclaimed delivery lock from sess-a"
    assert_includes audit, (@t0 + 3600).utc.iso8601
  end

  def test_takeover_records_new_owner_provenance
    Lock.acquire(@dir, session: "sess-a", now: @t0, harness: "claude")
    force_mtime(@t0)
    status, data = Lock.takeover(@dir, session: "sess-b", ttl: 1800, now: @t0 + 3600,
                                 harness: "codex", agent: "enforcer")
    assert_equal :taken, status
    assert_equal "codex", data["owner_harness"]
    assert_equal "enforcer", data["owner_agent"]
  end

  def test_who_reports_none_corrupt_legacy_and_fresh_state_without_touching_lock
    assert_equal "none", Lock.who(@dir, now: @t0)["state"]
    File.write(File.join(@dir, "delivery.lock"), "not-json")
    assert_equal "corrupt", Lock.who(@dir, now: @t0)["state"]
    File.write(File.join(@dir, "delivery.lock"), JSON.generate(
      "owner_session" => "legacy", "delegates" => ["sub-1"]
    ))
    force_mtime(@t0)
    before = File.mtime(File.join(@dir, "delivery.lock"))
    result = Lock.who(@dir, ttl: 1800, now: @t0 + 10)
    assert_equal "fresh", result["state"]
    assert_equal "unknown", result["owner"]["harness"]
    assert_equal "legacy", result["owner_session"]
    assert_equal "sub-1", result["delegates"].first["session"]
    assert_equal @t0.utc.iso8601, result["heartbeat_at"]
    assert_equal [], result["claims"]
    assert_equal before, File.mtime(File.join(@dir, "delivery.lock"))
    assert_equal "stale", Lock.who(@dir, ttl: 1800, now: @t0 + 3600)["state"]
  end

  private

  def force_mtime(time)
    FileUtils.touch(File.join(@dir, "delivery.lock"), mtime: time)
  end
end
