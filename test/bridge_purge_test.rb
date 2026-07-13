require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require_relative "../scripts/lib/bridge"
require_relative "../scripts/lib/worktree"
require_relative "../scripts/lib/lock"

# Tests for the terminal-state bridge purge (intent 80, replacing intent 67's
# age window).
#
# A bridge is purged ONLY when its intent is terminal: its id is not in its
# store's INDEX.md `## Active` block. An Active intent's bridge is kept (it is the
# continuation signal and the anti-collision lock), and the current session's own
# bridge is never purged. Malformed or store-less bridges are junk and purged.
class BridgePurgeTest < Minitest::Test
  def setup
    @store = Dir.mktmpdir("bridge-purge-store")
    @store = File.join(@store, "store")
    FileUtils.mkdir_p(@store)
    @intent_dir = File.join(@store, "80--demo")
    FileUtils.mkdir_p(@intent_dir)
    File.write(File.join(@intent_dir, "80--demo.md"), "## Intent\nDemo\n")
    @tmp = Dir.mktmpdir("bridge-purge-tmp")
    @saved_plastic_tmp = ENV["PLASTIC_TMP"]
    ENV["PLASTIC_TMP"] = @tmp
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
    FileUtils.rm_rf(File.dirname(@store))
    FileUtils.rm_rf(@tmp)
    @saved_plastic_tmp.nil? ? ENV.delete("PLASTIC_TMP") : ENV["PLASTIC_TMP"] = @saved_plastic_tmp
    @saved_session.nil? ? ENV.delete("CLAUDE_CODE_SESSION_ID") : ENV["CLAUDE_CODE_SESSION_ID"] = @saved_session
    Worktree.define_singleton_method(:provision, @real_provision) if @real_provision
    Worktree.define_singleton_method(:release, @real_release) if @real_release
  end

  # Write a minimal valid bridge for `session` pointing at intent `id` in `store`.
  def seed_bridge(session, id: "80", store: @store)
    data = {
      "session" => session,
      "intent" => { "id" => id, "dir" => "#{id}--demo", "store" => store, "name" => "demo" },
      "build" => { "auto" => false },
    }
    Bridge.write(session, data)
    Bridge.path(session, intent_id: id)
  end

  def seed_raw(session, contents)
    p = Bridge.path(session)
    File.write(p, contents)
    p
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

  # --- shared INDEX entry matcher (intent 188, D9/D12/D13) --------------------

  def test_intent_active_recognizes_hyphen_separator
    File.write(File.join(File.dirname(@store), "INDEX.md"), <<~MD)
      ## Active
      - [80 - Demo intent](store/80--demo/80--demo.md) - note

      ## Future
      _(none)_
    MD
    assert Bridge.intent_active?("80", store: @store),
      "a plain-hyphen ## Active line must be recognized as active (D13 hardening)"
  end

  def test_index_entry_match_accepts_em_dash_and_hyphen_rejects_missing_separator
    em_dash = Bridge.index_entry_match("- [80 — Title](path)")
    hyphen = Bridge.index_entry_match("- [80 - Title](path)")
    none = Bridge.index_entry_match("- [80 Title](path)")

    refute_nil em_dash
    assert_equal %w[80 Title path], [em_dash[1], em_dash[2], em_dash[3]]
    refute_nil hyphen
    assert_equal %w[80 Title path], [hyphen[1], hyphen[2], hyphen[3]]
    assert_nil none, "a line with no id/title separator must not match"
  end

  # --- purge_done_bridges ----------------------------------------------------

  def test_purges_terminal_intent
    write_index_active # nothing active
    f = seed_bridge("terminal", id: "80")
    Bridge.purge_done_bridges(session: "current")
    refute File.exist?(f)
  end

  def test_keeps_active_intent_via_index
    write_index_active("80")
    f = seed_bridge("live", id: "80")
    Bridge.purge_done_bridges(session: "current")
    assert File.exist?(f), "an Active intent's bridge must be kept"
  end

  def test_never_removes_current_session
    write_index_active # nothing active, so the only safety left is current-session
    f = seed_bridge("current", id: "80")
    Bridge.purge_done_bridges(session: "current")
    assert File.exist?(f), "current session bridge must never be purged"
  end

  def test_purges_malformed_json
    f = seed_raw("garbage", "}{not json")
    Bridge.purge_done_bridges(session: "current")
    refute File.exist?(f)
  end

  def test_purges_bridge_missing_store
    f = seed_raw("nostore", JSON.generate("session" => "nostore",
                                          "intent" => { "id" => "80", "name" => "demo" }))
    Bridge.purge_done_bridges(session: "current")
    refute File.exist?(f), "a bridge with no intent.store is junk and purged"
  end

  def test_purges_bridge_blank_id
    f = seed_raw("noid", JSON.generate("session" => "noid",
                                       "intent" => { "id" => "", "store" => @store }))
    Bridge.purge_done_bridges(session: "current")
    refute File.exist?(f), "a bridge with a blank intent.id is junk and purged"
  end

  def test_never_purges_a_bridge_whose_intent_still_holds_a_delivery_lock
    write_index_active # 80 is TERMINAL, so the bridge would normally purge
    f = seed_bridge("other-sess", id: "80")
    Lock.acquire(@intent_dir, session: "other-sess")
    removed = Bridge.purge_done_bridges(session: "current", tmp: @tmp)
    refute_includes removed, f,
                    "a held delivery lock makes the bridge purge-ineligible (D6)"
    assert File.exist?(f)
  end

  # Intent 93 D4/AC5: the post-done window is bounded by the delivery lock,
  # `[INDEX terminal -> Lock.release]`. The OPEN edge (above) keeps the terminal
  # bridge while the lock is held; the CLOSE edge (here) proves that once the
  # owner releases the lock the terminal bridge becomes purge-eligible again.
  def test_purges_a_terminal_bridge_once_the_delivery_lock_is_released
    write_index_active # 80 is TERMINAL (not Active)
    f = seed_bridge("other-sess", id: "80")

    # Window OPEN: lock held -> no purge.
    Lock.acquire(@intent_dir, session: "other-sess")
    removed = Bridge.purge_done_bridges(session: "current", tmp: @tmp)
    refute_includes removed, f, "window open: a held lock keeps the terminal bridge"
    assert File.exist?(f)

    # Window CLOSES on Lock.release -> the terminal bridge is now purged.
    assert_equal :released, Lock.release(@intent_dir, session: "other-sess")
    removed = Bridge.purge_done_bridges(session: "current", tmp: @tmp)
    assert_includes removed, f, "window closed: after Lock.release the bridge is purge-eligible"
    refute File.exist?(f)
  end

  def test_returns_removed_paths
    write_index_active("80")
    keep = seed_bridge("live", id: "80")
    gone = seed_bridge("terminal", id: "99")
    removed = Bridge.purge_done_bridges(session: "current")
    assert_includes removed, gone
    refute_includes removed, keep
  end

  def test_enoent_midsweep_does_not_raise
    write_index_active # nothing active
    seed_bridge("stale-a", id: "80")
    seed_bridge("stale-b", id: "80")
    Bridge.purge_done_bridges(session: "current")
    removed = nil
    assert_silent { removed = Bridge.purge_done_bridges(session: "current") }
    assert_kind_of Array, removed
  end

  def test_non_raising_on_bad_tmp
    removed = nil
    assert_silent do
      removed = Bridge.purge_done_bridges(session: "current",
                                          tmp: "/no/such/dir/at/all")
    end
    assert_kind_of Array, removed
    assert_empty removed
  end

  # --- arm_auto / disarm_auto wiring -----------------------------------------

  def test_arm_auto_purges_terminal_siblings
    write_index_active # the sibling intent 99 is NOT active
    stale = seed_bridge("old-sibling", id: "99")
    data = Bridge.arm_auto("armer", intent_id: "80", intent_dir: @intent_dir,
                           store: @store, name: "demo")
    refute File.exist?(stale), "arm_auto should purge terminal siblings"
    assert File.exist?(Bridge.path(data["session"], intent_id: data["intent"]["id"])),
           "armed bridge must survive"
  end

  def test_disarm_auto_purges_terminal_siblings_and_keeps_self
    Bridge.arm_auto("delivering", intent_id: "80", intent_dir: @intent_dir,
                    store: @store, name: "demo")
    write_index_active # sibling 99 not active
    stale = seed_bridge("old-sibling", id: "99")
    Bridge.disarm_auto("delivering", intent_id: "80")
    refute File.exist?(stale), "disarm_auto should purge terminal siblings"
    self_bridge = Bridge.read("delivering", intent_id: "80")
    refute_nil self_bridge, "current bridge must remain readable after disarm"
    assert_equal false, self_bridge["build"]["auto"]
  end
end
