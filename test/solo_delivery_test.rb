require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/bridge"
require_relative "../scripts/lib/lock"

# Unit tests for Bridge.solo_delivery? (intent 128): positive-only confirmation
# that exactly one session is delivering, scanned from durable delivery.lock
# files across injected scan_roots. Hermetic throughout: every root is a
# mktmpdir, never the real ~/.plastic.
class SoloDeliveryTest < Minitest::Test
  def setup
    @store_a = Dir.mktmpdir("solo-store-a")
    @store_b = Dir.mktmpdir("solo-store-b")
  end

  def teardown
    FileUtils.rm_rf(@store_a)
    FileUtils.rm_rf(@store_b)
  end

  def intent_dir(store, id)
    d = File.join(store, "#{id}--demo")
    FileUtils.mkdir_p(d)
    d
  end

  def test_one_fresh_own_lock_is_solo
    Lock.acquire(intent_dir(@store_a, "1"), session: "sess-1")
    assert Bridge.solo_delivery?(scan_roots: [@store_a, @store_b], session: "sess-1")
  end

  def test_two_fresh_locks_same_owner_is_not_solo
    Lock.acquire(intent_dir(@store_a, "1"), session: "sess-1")
    Lock.acquire(intent_dir(@store_a, "2"), session: "sess-1")
    refute Bridge.solo_delivery?(scan_roots: [@store_a, @store_b], session: "sess-1"),
           "two fresh locks under one owner reads as parallel-in-play (AC2)"
  end

  def test_one_fresh_lock_owned_by_someone_else_is_not_solo
    Lock.acquire(intent_dir(@store_a, "1"), session: "other-session")
    refute Bridge.solo_delivery?(scan_roots: [@store_a, @store_b], session: "sess-1")
  end

  def test_one_fresh_own_lock_with_a_delegate_is_not_solo
    dir = intent_dir(@store_a, "1")
    Lock.acquire(dir, session: "sess-1")
    Lock.add_delegate(dir, delegate: "sub-1", session: "sess-1")
    refute Bridge.solo_delivery?(scan_roots: [@store_a, @store_b], session: "sess-1"),
           "a non-empty delegates array is a team, not solo (AC3)"
  end

  def test_blank_session_is_never_solo
    Lock.acquire(intent_dir(@store_a, "1"), session: "sess-1")
    refute Bridge.solo_delivery?(scan_roots: [@store_a, @store_b], session: "")
    refute Bridge.solo_delivery?(scan_roots: [@store_a, @store_b], session: nil)
  end

  def test_zero_locks_is_not_solo
    refute Bridge.solo_delivery?(scan_roots: [@store_a, @store_b], session: "sess-1"),
           "no fresh lock anywhere means solo cannot be positively confirmed"
  end

  def test_stale_lock_does_not_count_toward_solo
    dir = intent_dir(@store_a, "1")
    Lock.acquire(dir, session: "sess-1")
    FileUtils.touch(Lock.path(dir), mtime: Time.now - 4000)
    refute Bridge.solo_delivery?(scan_roots: [@store_a, @store_b], session: "sess-1")
  end

  def test_a_fresh_lock_across_two_scan_roots_still_counts_as_one_session
    Lock.acquire(intent_dir(@store_a, "1"), session: "sess-1")
    assert Bridge.solo_delivery?(scan_roots: [@store_a, @store_a, @store_b], session: "sess-1"),
           "duplicate scan roots must not double count the same lock"
  end

  def test_rescues_a_scan_error_to_false
    bad_root = Object.new # File.join raises TypeError on a non-path object
    refute Bridge.solo_delivery?(scan_roots: [bad_root], session: "sess-1")
  end

  # Hardening (review finding 2): a fresh-but-unreadable lock is real
  # ambiguity, not an absence. Dropping it silently could leave exactly one
  # READABLE lock (mine) and misconfirm solo while a second, corrupt-but-live
  # lock is genuinely in play elsewhere.
  def test_fresh_but_corrupt_lock_elsewhere_is_not_solo
    Lock.acquire(intent_dir(@store_a, "1"), session: "sess-1") # my own valid fresh lock
    corrupt_dir = intent_dir(@store_a, "2")
    File.write(Lock.path(corrupt_dir), "{ not json")
    refute Bridge.solo_delivery?(scan_roots: [@store_a, @store_b], session: "sess-1"),
           "a fresh but unreadable lock elsewhere must keep the gate fail-closed"
  end
end
