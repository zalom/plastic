require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require_relative "../scripts/lib/lock"
require_relative "../scripts/lib/bridge"

# Lease heartbeat wiring (intent 108 D1, moved in intent 302): owner tool activity
# refreshes the delivery.lock mtime through the PostToolUse `record` hook, the one
# write-path hook left after the edit-path gates were removed. Hermetic: bridges live
# in an injected PLASTIC_TMP; the intent store lives in a mktmpdir.
class LockHeartbeatTest < Minitest::Test
  RECORD = File.expand_path("../scripts/hook-record", __dir__)

  def setup
    @tmp = Dir.mktmpdir("hb-bridge-tmp")
    @home = Dir.mktmpdir("hb-home")
    @store = File.join(@home, ".plastic", "projects", "demo", "store")
    @intent_dir = File.join(@store, "96--demo")
    FileUtils.mkdir_p(@intent_dir)
    File.write(File.join(@intent_dir, "96--demo.md"), "## Intent\nDemo\n")
    File.write(File.join(File.dirname(@store), "INDEX.md"),
               "## Active\n- [96 - demo](96--demo/96--demo.md)\n\n## Future\n")
    @old = Time.now - 900
    Lock.acquire(@intent_dir, session: "sess-1")
    FileUtils.touch(Lock.path(@intent_dir), mtime: @old)
    Bridge.write("sess-1", bridge_data, tmp: @tmp)
  end

  def teardown
    FileUtils.rm_rf(@tmp)
    FileUtils.rm_rf(@home)
  end

  def bridge_data
    { "session" => "sess-1",
      "intent" => { "id" => "96", "dir" => "96--demo", "store" => @store,
                    "name" => "demo" },
      "build" => { "stage" => "why", "auto" => false } }
  end

  def run_record(file, session: "sess-1")
    payload = JSON.generate("session_id" => session, "tool_input" => { "file_path" => file }, "cwd" => @home)
    Open3.capture3({ "PLASTIC_TMP" => @tmp, "CLAUDE_CODE_SESSION_ID" => nil, "HOME" => @home },
                   RbConfig.ruby, RECORD, stdin_data: payload)
  end

  def lock_mtime
    File.mtime(Lock.path(@intent_dir)).to_i
  end

  # Intent 302 (spec D10): the lock gate's allow path was the only per-edit refresher
  # of the lease. With the gate gone, `record` refreshes it for any write inside the
  # locked intent dir, so a live delivery never reads stale to end-intent or plastic-lock.
  def test_owner_write_inside_the_intent_dir_refreshes_the_lease
    file = File.join(@intent_dir, "resources", "note.md")
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, "x")
    run_record(file)
    assert_operator lock_mtime, :>, @old.to_i, "record must heartbeat the owner's delivery.lock"
  end

  def test_owner_lifecycle_write_refreshes_the_lease_and_still_appends_the_savepoint
    file = File.join(@intent_dir, "spec.md")
    File.write(file, "# Spec\nreal\n")
    run_record(file)
    assert_operator lock_mtime, :>, @old.to_i
    assert_includes File.read(File.join(@intent_dir, "savepoint.md")), "spec.md created"
  end

  def test_foreign_session_write_does_not_refresh_the_lease
    file = File.join(@intent_dir, "spec.md")
    File.write(file, "# Spec\nreal\n")
    run_record(file, session: "stranger")
    assert_equal @old.to_i, lock_mtime, "a stranger must not touch the owner's heartbeat"
  end

  def test_write_outside_any_intent_dir_touches_no_lock
    file = File.join(@home, "apps", "demo", "app.rb")
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, "puts 1\n")
    run_record(file)
    assert_equal @old.to_i, lock_mtime, "a project-code write is not inside the intent dir"
  end

  # --- lease semantics against a second session (pure, injected clock) -------

  def test_second_session_refused_while_fresh_reclaim_only_after_ttl
    t0 = Time.now
    refute Lock.holds?(@intent_dir, session: "sess-2")
    status, _ = Lock.takeover(@intent_dir, session: "sess-2", ttl: 1800, now: t0)
    assert_equal :fresh, status, "takeover refused while the lease is fresh"

    FileUtils.touch(Lock.path(@intent_dir), mtime: t0 - 3600)
    status, data = Lock.takeover(@intent_dir, session: "sess-2", ttl: 1800, now: t0)
    assert_equal :taken, status
    assert_equal "sess-2", data["owner_session"]
  end
end
