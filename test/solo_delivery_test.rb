require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/bridge"
require_relative "../scripts/lib/db"

# Unit tests for Bridge.solo_delivery? (intent 128; cutover intent 41
# ACTION_10): positive-only confirmation that exactly one session is
# delivering, scanned from durable `lock_leases` delivery-grain rows across
# injected scan_roots (each a STORE dir, one plastic.db per store). Hermetic
# throughout: every root is a mktmpdir, never the real ~/.plastic.
class SoloDeliveryTest < Minitest::Test
  def setup
    @home_a = Dir.mktmpdir("solo-home-a")
    @store_a = File.join(@home_a, "store")
    @home_b = Dir.mktmpdir("solo-home-b")
    @store_b = File.join(@home_b, "store")
  end

  def teardown
    FileUtils.rm_rf(@home_a)
    FileUtils.rm_rf(@home_b)
  end

  def intent_dir(store, id)
    d = File.join(store, "#{id}--demo")
    FileUtils.mkdir_p(d)
    d
  end

  def acquire(store_home, intent_id, session:, now: Time.now)
    conn = Plastic::DB.connect(store_home)
    Plastic::DB::Leases.acquire(conn, intent_id, session: session, host: "h", now: now)
  end

  def test_one_fresh_own_lock_is_solo
    intent_dir(@store_a, "1")
    acquire(@home_a, "1", session: "sess-1")
    assert Bridge.solo_delivery?(scan_roots: [@store_a, @store_b], session: "sess-1")
  end

  def test_two_fresh_locks_same_owner_is_not_solo
    intent_dir(@store_a, "1")
    intent_dir(@store_a, "2")
    acquire(@home_a, "1", session: "sess-1")
    acquire(@home_a, "2", session: "sess-1")
    refute Bridge.solo_delivery?(scan_roots: [@store_a, @store_b], session: "sess-1"),
           "two fresh leases under one owner reads as parallel-in-play (AC2)"
  end

  def test_one_fresh_lock_owned_by_someone_else_is_not_solo
    intent_dir(@store_a, "1")
    acquire(@home_a, "1", session: "other-session")
    refute Bridge.solo_delivery?(scan_roots: [@store_a, @store_b], session: "sess-1")
  end

  def test_one_fresh_own_lock_with_a_delegate_is_not_solo
    intent_dir(@store_a, "1")
    acquire(@home_a, "1", session: "sess-1")
    conn = Plastic::DB.connect(@home_a)
    Plastic::DB::Leases.add_delegate(conn, "1", delegate: "sub-1", session: "sess-1")
    refute Bridge.solo_delivery?(scan_roots: [@store_a, @store_b], session: "sess-1"),
           "a registered delegate is a team, not solo (AC3)"
  end

  def test_blank_session_is_never_solo
    intent_dir(@store_a, "1")
    acquire(@home_a, "1", session: "sess-1")
    refute Bridge.solo_delivery?(scan_roots: [@store_a, @store_b], session: "")
    refute Bridge.solo_delivery?(scan_roots: [@store_a, @store_b], session: nil)
  end

  def test_zero_locks_is_not_solo
    refute Bridge.solo_delivery?(scan_roots: [@store_a, @store_b], session: "sess-1"),
           "no fresh lease anywhere means solo cannot be positively confirmed"
  end

  def test_expired_lock_does_not_count_toward_solo
    intent_dir(@store_a, "1")
    acquire(@home_a, "1", session: "sess-1", now: Time.now - 4000)
    refute Bridge.solo_delivery?(scan_roots: [@store_a, @store_b], session: "sess-1")
  end

  def test_a_fresh_lock_across_two_scan_roots_still_counts_as_one_session
    intent_dir(@store_a, "1")
    acquire(@home_a, "1", session: "sess-1")
    assert Bridge.solo_delivery?(scan_roots: [@store_a, @store_a, @store_b], session: "sess-1"),
           "duplicate scan roots must not double count the same lease"
  end

  def test_rescues_a_scan_error_to_false
    bad_root = Object.new
    def bad_root.to_s
      raise "boom"
    end
    refute Bridge.solo_delivery?(scan_roots: [bad_root], session: "sess-1")
  end

  # A live lease in a DIFFERENT store than the acting session's own is still
  # counted correctly (each scan_root opens its own store's DB); confirms the
  # per-store connection fan-out does not silently drop a rival elsewhere.
  def test_a_second_fresh_lock_in_a_different_store_still_defeats_solo
    intent_dir(@store_a, "1")
    intent_dir(@store_b, "2")
    acquire(@home_a, "1", session: "sess-1")
    acquire(@home_b, "2", session: "sess-1")
    refute Bridge.solo_delivery?(scan_roots: [@store_a, @store_b], session: "sess-1"),
           "a fresh lease under the same session in a second store is still parallel-in-play"
  end
end
