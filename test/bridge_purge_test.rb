require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require_relative "../scripts/lib/bridge"

# Tests for the stale-bridge purge added in intent 67.
#
# The bridge file is ephemeral live-session state, not a continuation source
# (an intent resumes from savepoint.md), so the purge rule is purely age-based:
# a bridge older than PURGE_AGE_SECONDS (48h) is removed regardless of arm state;
# anything newer is kept; the current session's own bridge is never removed.
class BridgePurgeTest < Minitest::Test
  AGE    = Bridge::PURGE_AGE_SECONDS
  OLD    = AGE + 3600   # past the cutoff
  RECENT = 60           # well within the cutoff

  def setup
    @store = Dir.mktmpdir("bridge-purge-store")
    @intent_dir = File.join(@store, "67--demo")
    FileUtils.mkdir_p(@intent_dir)
    File.write(File.join(@intent_dir, "67--demo.md"), "## Intent\nDemo\n")
    @tmp = Dir.mktmpdir("bridge-purge-tmp")
    @saved_plastic_tmp = ENV["PLASTIC_TMP"]
    ENV["PLASTIC_TMP"] = @tmp
  end

  def teardown
    FileUtils.rm_rf(@store)
    FileUtils.rm_rf(@tmp)
    @saved_plastic_tmp.nil? ? ENV.delete("PLASTIC_TMP") : ENV["PLASTIC_TMP"] = @saved_plastic_tmp
  end

  # Write a minimal valid bridge for `session`, backdated by `age_seconds`.
  def seed_bridge(session, auto:, age_seconds:)
    data = {
      "session" => session,
      "intent" => { "id" => "67", "dir" => "67--demo", "store" => @store, "name" => "demo" },
      "build" => { "auto" => auto },
    }
    Bridge.write(session, data)
    age_file(Bridge.path(session), age_seconds)
    Bridge.path(session)
  end

  def seed_raw(session, contents, age_seconds:)
    p = Bridge.path(session)
    File.write(p, contents)
    age_file(p, age_seconds)
    p
  end

  def age_file(path, age_seconds)
    t = Time.now - age_seconds
    File.utime(t, t, path)
  end

  def test_removes_old_disarmed
    f = seed_bridge("stale", auto: false, age_seconds: OLD)
    Bridge.purge_stale_bridges(session: "current")
    refute File.exist?(f)
  end

  def test_removes_old_auto_armed
    # Age wins over arm state: a 48h-old auto-armed bridge is an abandoned run,
    # and continuation never relies on it, so it is purged.
    f = seed_bridge("old-auto", auto: true, age_seconds: OLD)
    Bridge.purge_stale_bridges(session: "current")
    refute File.exist?(f)
  end

  def test_keeps_recent_auto_armed
    f = seed_bridge("live", auto: true, age_seconds: RECENT)
    Bridge.purge_stale_bridges(session: "current")
    assert File.exist?(f)
  end

  def test_keeps_recent_non_auto
    f = seed_bridge("recent", auto: false, age_seconds: RECENT)
    Bridge.purge_stale_bridges(session: "current")
    assert File.exist?(f)
  end

  def test_never_removes_current_session
    f = seed_bridge("current", auto: false, age_seconds: OLD)
    Bridge.purge_stale_bridges(session: "current")
    assert File.exist?(f), "current session bridge must never be purged"
  end

  def test_removes_unparseable_old
    f = seed_raw("garbage-old", "}{not json", age_seconds: OLD)
    Bridge.purge_stale_bridges(session: "current")
    refute File.exist?(f)
  end

  def test_keeps_unparseable_recent
    f = seed_raw("garbage-new", "}{not json", age_seconds: RECENT)
    Bridge.purge_stale_bridges(session: "current")
    assert File.exist?(f)
  end

  def test_enoent_midsweep_does_not_raise
    seed_bridge("stale-a", auto: false, age_seconds: OLD)
    seed_bridge("stale-b", auto: false, age_seconds: OLD)
    Bridge.purge_stale_bridges(session: "current")
    removed = nil
    assert_silent { removed = Bridge.purge_stale_bridges(session: "current") }
    assert_kind_of Array, removed
  end

  def test_returns_removed_paths
    f = seed_bridge("stale", auto: false, age_seconds: OLD)
    keep = seed_bridge("live", auto: true, age_seconds: RECENT)
    removed = Bridge.purge_stale_bridges(session: "current")
    assert_includes removed, f
    refute_includes removed, keep
  end

  def test_arm_auto_purges_siblings
    stale = seed_bridge("old-sibling", auto: false, age_seconds: OLD)
    data = Bridge.arm_auto("armer", intent_id: "67", intent_dir: @intent_dir, store: @store, name: "demo")
    refute File.exist?(stale), "arm_auto should purge stale siblings"
    assert File.exist?(Bridge.path(data["session"])), "armed bridge must survive"
  end

  def test_disarm_auto_purges_siblings_and_keeps_self
    Bridge.arm_auto("delivering", intent_id: "67", intent_dir: @intent_dir, store: @store, name: "demo")
    stale = seed_bridge("old-sibling", auto: false, age_seconds: OLD)
    Bridge.disarm_auto("delivering")
    refute File.exist?(stale), "disarm_auto should purge stale siblings"
    self_bridge = Bridge.read("delivering")
    refute_nil self_bridge, "current bridge must remain readable after disarm"
    assert_equal false, self_bridge["build"]["auto"]
  end
end
