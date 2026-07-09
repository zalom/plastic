require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/bridge"
require_relative "../scripts/lib/worktree"
require_relative "../scripts/lib/lock"
require_relative "../scripts/lib/db"

# Tests for the terminal-state session GC (intent 41 cutover of intent 80's
# terminal-state bridge purge, replacing intent 67's age window).
#
# A session row is purged ONLY when its intent is terminal: its id is not in
# its store's INDEX.md `## Active` block. An Active intent's row is kept (it
# is the continuation signal and the anti-collision lock), and the current
# session's own row is never purged. A row with no resolvable intent id is
# junk and purged.
#
# The old /tmp-era malformed-JSON and missing-store failure modes are
# structurally impossible now: a `sessions` row is a real DB row, never a
# hand-parsed JSON file, and it always lives inside ONE store's own DB, so
# "a bridge with no intent.store" cannot occur.
class BridgePurgeTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("bridge-purge-home")
    @store = File.join(@home, "store")
    FileUtils.mkdir_p(@store)
    @intent_dir = File.join(@store, "80--demo")
    FileUtils.mkdir_p(@intent_dir)
    File.write(File.join(@intent_dir, "80--demo.md"), "## Intent\nDemo\n")

    # Ambient-clear (intent 98 pattern): the arm tests below pass explicit
    # sessions, but a leaked CLAUDE_CODE_SESSION_ID must never reach a write.
    @saved_session = ENV["CLAUDE_CODE_SESSION_ID"]
    ENV.delete("CLAUDE_CODE_SESSION_ID")

    # Neutralize real worktree git ops (intent 108 hermeticity fix): the arm
    # wiring tests below used to run the REAL provision, which planted store
    # worktrees like ~/.plastic/.worktrees/80--demo in the LIVE global store.
    @real_provision = Worktree.method(:provision)
    @real_release = Worktree.method(:release)
    Worktree.define_singleton_method(:provision) { |d, *_a, **_kw| d }
    Worktree.define_singleton_method(:release) { |d, *_a, **_kw| d }
  end

  def teardown
    FileUtils.rm_rf(@home)
    @saved_session.nil? ? ENV.delete("CLAUDE_CODE_SESSION_ID") : ENV["CLAUDE_CODE_SESSION_ID"] = @saved_session
    Worktree.define_singleton_method(:provision, @real_provision) if @real_provision
    Worktree.define_singleton_method(:release, @real_release) if @real_release
  end

  # Register a minimal session row for `session_id` pointing at intent `id`.
  def seed_session(session_id, id: "80", cwd: @intent_dir)
    conn = Plastic::DB.connect(@home)
    Plastic::DB::Sessions.register(conn, session_id: session_id, host: "h", pid: 1,
                                    cwd: cwd, active_intent_id: id, auto: false, now: Time.now)
  end

  def row_exists?(session_id)
    conn = Plastic::DB.connect(@home)
    !Plastic::DB::Sessions.active_for(conn, session: session_id, cwd: nil).nil?
  end

  # Write an INDEX.md at the parent of @store with `ids` listed under ## Active.
  def write_index_active(*ids)
    lines = ["## Active"]
    ids.each { |i| lines << "- [#{i} — Demo intent #{i}](store/#{i}--demo/#{i}--demo.md) — note" }
    lines << ""
    lines << "## Future"
    lines << "_(none)_"
    File.write(File.join(File.dirname(@store), "INDEX.md"), lines.join("\n") + "\n")
  end

  # --- intent_active? --------------------------------------------------------

  def test_intent_active_via_index_active_ids_seam
    assert Bridge.intent_active?("80", store: @store, index_active_ids: ["80", "69"])
    refute Bridge.intent_active?("80", store: @store, index_active_ids: ["69"])
  end

  def test_intent_active_reads_index_active_block
    write_index_active("80")
    assert Bridge.intent_active?("80", store: @store)
    refute Bridge.intent_active?("99", store: @store)
  end

  def test_intent_active_false_when_index_missing
    refute Bridge.intent_active?("80", store: @store)
  end

  def test_intent_active_only_scans_active_block
    # An id in a later section (## Future) must NOT count as Active.
    File.write(File.join(File.dirname(@store), "INDEX.md"), <<~IDX)
      ## Active
      _(none)_

      ## Future
      - [80 — parked](store/80--demo/80--demo.md) — note
    IDX
    refute Bridge.intent_active?("80", store: @store)
  end

  # --- purge_done_bridges ----------------------------------------------------

  def test_purges_terminal_intent
    write_index_active # nothing active
    seed_session("terminal", id: "80")
    Bridge.purge_done_bridges(session: "current", store: @store)
    refute row_exists?("terminal")
  end

  def test_keeps_active_intent_via_index
    write_index_active("80")
    seed_session("live", id: "80")
    Bridge.purge_done_bridges(session: "current", store: @store)
    assert row_exists?("live"), "an Active intent's session row must be kept"
  end

  def test_never_removes_current_session
    write_index_active # nothing active, so the only safety left is current-session
    seed_session("current", id: "80")
    Bridge.purge_done_bridges(session: "current", store: @store)
    assert row_exists?("current"), "current session row must never be purged"
  end

  def test_purges_row_with_blank_intent_id
    seed_session("noid", id: "")
    Bridge.purge_done_bridges(session: "current", store: @store)
    refute row_exists?("noid"), "a row with a blank active_intent_id is junk and purged"
  end

  def test_never_purges_a_row_whose_intent_still_holds_a_delivery_lock
    write_index_active # 80 is TERMINAL, so the row would normally purge
    seed_session("other-sess", id: "80")
    Lock.acquire(@intent_dir, session: "other-sess")
    removed = Bridge.purge_done_bridges(session: "current", store: @store)
    refute_includes removed, "other-sess",
                    "a held delivery lock makes the row purge-ineligible (D6)"
    assert row_exists?("other-sess")
  end

  # Intent 93 D4/AC5: the post-done window is bounded by the delivery lock,
  # `[INDEX terminal -> Lock.release]`. The OPEN edge (above) keeps the terminal
  # row while the lock is held; the CLOSE edge (here) proves that once the
  # owner releases the lock the terminal row becomes purge-eligible again.
  def test_purges_a_terminal_row_once_the_delivery_lock_is_released
    write_index_active # 80 is TERMINAL (not Active)
    seed_session("other-sess", id: "80")

    # Window OPEN: lock held -> no purge.
    Lock.acquire(@intent_dir, session: "other-sess")
    removed = Bridge.purge_done_bridges(session: "current", store: @store)
    refute_includes removed, "other-sess", "window open: a held lock keeps the terminal row"
    assert row_exists?("other-sess")

    # Window CLOSES on Lock.release -> the terminal row is now purged.
    assert_equal :released, Lock.release(@intent_dir, session: "other-sess")
    removed = Bridge.purge_done_bridges(session: "current", store: @store)
    assert_includes removed, "other-sess", "window closed: after Lock.release the row is purge-eligible"
    refute row_exists?("other-sess")
  end

  def test_returns_removed_session_ids
    write_index_active("80")
    seed_session("live", id: "80")
    intent_dir_99 = File.join(@store, "99--demo")
    FileUtils.mkdir_p(intent_dir_99)
    seed_session("terminal", id: "99")
    removed = Bridge.purge_done_bridges(session: "current", store: @store)
    assert_includes removed, "terminal"
    refute_includes removed, "live"
  end

  def test_non_raising_on_bad_store
    removed = nil
    assert_silent do
      removed = Bridge.purge_done_bridges(session: "current", store: "/no/such/dir/at/all/store")
    end
    assert_kind_of Array, removed
    assert_empty removed
  end

  # --- arm_auto / disarm_auto wiring -----------------------------------------

  def test_arm_auto_purges_terminal_siblings
    write_index_active # the sibling intent 99 is NOT active
    intent_dir_99 = File.join(@store, "99--demo")
    FileUtils.mkdir_p(intent_dir_99)
    seed_session("old-sibling", id: "99")
    data = Bridge.arm_auto("armer", intent_id: "80", intent_dir: @intent_dir,
                           store: @store, name: "demo")
    refute row_exists?("old-sibling"), "arm_auto should purge terminal siblings"
    refute_nil data
  end

  def test_disarm_auto_purges_terminal_siblings_and_keeps_self
    Bridge.arm_auto("delivering", intent_id: "80", intent_dir: @intent_dir,
                    store: @store, name: "demo")
    write_index_active # sibling 99 not active
    intent_dir_99 = File.join(@store, "99--demo")
    FileUtils.mkdir_p(intent_dir_99)
    seed_session("old-sibling", id: "99")
    Bridge.disarm_auto("delivering", intent_id: "80", store: @store)
    refute row_exists?("old-sibling"), "disarm_auto should purge terminal siblings"
  end
end
