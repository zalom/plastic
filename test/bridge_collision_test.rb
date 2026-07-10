# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require_relative "../scripts/lib/bridge"
require_relative "../scripts/lib/worktree"
require_relative "../scripts/lib/db"

# Regression test for intent 131 (two intents delivered concurrently under ONE
# session id used to clobber a single shared /tmp bridge file), re-verified
# against the `sessions`-table storage of intent 41's cutover. The fix keys
# each armed intent by `"#{session}--#{intent_id}"` (sessions.session_id is
# UNIQUE, so this is the only way one bare session owns several live rows) and
# teaches Sessions.active_for to pick among a session's several rows by cwd
# (worktree.code > intent dir), tested exhaustively in db_sessions_test.rb
# (ACTION_4). This file re-verifies the same invariants through Bridge's public
# surface (arm_auto/discover_bridge/purge_done_bridges), plus the gate
# functions resolving to the correct sibling.
#
# Storage is now per-store (one plastic.db per store), so the old /tmp-era
# CROSS-STORE disambiguation and legacy single-key fallback scenarios no
# longer apply: a session row lives in exactly one store's DB, so there is no
# way for a caller connected to store A to ever see store B's rows at all
# (structurally impossible, not merely untested).
class BridgeCollisionTest < Minitest::Test
  # This file simulates collisions/siblings within ONE process, never real
  # cross-process contention (that is db_contention_smoke_test.rb's job, and
  # it legitimately wants the real production busy_timeout). Every write here
  # goes through many short-lived, never-closed connections to the SAME
  # store db, so a stubbed-in tiny busy_timeout keeps any incidental SQLITE_BUSY
  # retry fast and deterministic instead of paying D1's real 5000ms floor per
  # attempt. The assertions below are unchanged: collision/tiebreak outcomes,
  # never timing.
  TEST_BUSY_TIMEOUT_MS = 25

  def setup
    @saved_session = ENV["CLAUDE_CODE_SESSION_ID"]
    ENV.delete("CLAUDE_CODE_SESSION_ID")

    @home = Dir.mktmpdir("bridge-collision-home")
    @store = File.join(@home, "store")
    FileUtils.mkdir_p(@store)

    @dirA = File.join(@store, "201--demo-a")
    @dirB = File.join(@store, "202--demo-b")
    FileUtils.mkdir_p(@dirA)
    FileUtils.mkdir_p(@dirB)
    File.write(File.join(@dirA, "201--demo-a.md"), "## Intent\nA\n")
    File.write(File.join(@dirB, "202--demo-b.md"), "## Intent\nB\n")

    write_index_active(%w[201 202])

    # Neutralize real worktree git ops (no real git, no touching ~/.plastic).
    @real_provision = Worktree.method(:provision)
    @real_release = Worktree.method(:release)
    Worktree.define_singleton_method(:provision) { |d, *_a, **_kw| d }
    Worktree.define_singleton_method(:release) { |d, *_a, **_kw| d }

    # Route every connection this test's calls open (direct, and every one
    # opened deep inside Bridge.arm_auto/discover_bridge/purge_done_bridges)
    # through the tiny test busy_timeout, without changing Bridge's or
    # Plastic::DB's production call sites.
    @real_connect = Plastic::DB.method(:connect)
    real_connect = @real_connect
    Plastic::DB.define_singleton_method(:connect) do |store_home, **kw|
      real_connect.call(store_home, **{ busy_timeout: TEST_BUSY_TIMEOUT_MS }.merge(kw))
    end
  end

  def teardown
    FileUtils.rm_rf(@home)
    @saved_session.nil? ? ENV.delete("CLAUDE_CODE_SESSION_ID") : ENV["CLAUDE_CODE_SESSION_ID"] = @saved_session
    Worktree.define_singleton_method(:provision, @real_provision) if @real_provision
    Worktree.define_singleton_method(:release, @real_release) if @real_release
    Plastic::DB.define_singleton_method(:connect, @real_connect) if @real_connect
  end

  def write_index_active(ids)
    lines = ["## Active"]
    ids.each { |id| lines << "- [#{id} — demo](store/#{id}--demo/#{id}--demo.md)" }
    lines << ""
    lines << "## Future"
    File.write(File.join(File.dirname(@store), "INDEX.md"), lines.join("\n") + "\n")
  end

  def seed_session(session_id:, intent_id:, cwd:, auto: true)
    conn = Plastic::DB.connect(@home)
    Plastic::DB::Sessions.register(conn, session_id: session_id, host: "h", pid: 1, cwd: cwd,
                                    active_intent_id: intent_id, auto: auto, now: Time.now)
  end

  # --- 1. two intents, one session, no clobber --------------------------------

  def test_two_intents_one_session_get_separate_rows
    session = "shared-session"
    Bridge.arm_auto(session, intent_id: "201", intent_dir: @dirA, store: @store, name: "demo-a")
    Bridge.arm_auto(session, intent_id: "202", intent_dir: @dirB, store: @store, name: "demo-b")

    conn = Plastic::DB.connect(@home)
    row_a = Plastic::DB::Sessions.active_for(conn, session: Bridge.session_key(session, "201"), cwd: nil)
    row_b = Plastic::DB::Sessions.active_for(conn, session: Bridge.session_key(session, "202"), cwd: nil)
    refute_nil row_a, "intent A's session row must exist"
    refute_nil row_b, "intent B's session row must exist"
    refute_equal row_a["session_id"], row_b["session_id"], "the two intents must not share one row"
    assert_equal "201", row_a["active_intent_id"], "A's row must still carry A's id (no clobber)"
    assert_equal "202", row_b["active_intent_id"], "B's row must still carry B's id (no clobber)"
  end

  # --- 2. discover_bridge resolves by cwd/worktree.code -----------------------

  def test_discover_resolves_by_cwd_worktree
    session = "wt-session"
    code_a = File.join(@home, "repo", ".claude", "worktrees", "201--demo-a")
    code_b = File.join(@home, "repo", ".claude", "worktrees", "202--demo-b")
    FileUtils.mkdir_p(code_a)
    FileUtils.mkdir_p(code_b)

    seed_session(session_id: Bridge.session_key(session, "201"), intent_id: "201", cwd: code_a)
    # B is registered LAST (newer last_seen_at), yet cwd inside A's worktree must still resolve A.
    seed_session(session_id: Bridge.session_key(session, "202"), intent_id: "202", cwd: code_b)

    found_a = Bridge.discover_bridge(session: session, cwd: code_a, store_home: @home)
    assert_equal "201", found_a.dig("intent", "id"),
                 "cwd inside A's worktree resolves to A even though B is newer"

    found_b = Bridge.discover_bridge(session: session, cwd: code_b, store_home: @home)
    assert_equal "202", found_b.dig("intent", "id"), "cwd inside B's worktree resolves to B"
  end

  # --- 3. gates resolve to the correct sibling --------------------------------

  def test_gates_resolve_to_correct_sibling
    session = "gate-session"
    code_a = File.join(@home, "repo", ".claude", "worktrees", "201--demo-a")
    code_b = File.join(@home, "repo", ".claude", "worktrees", "202--demo-b")
    FileUtils.mkdir_p(code_a)
    FileUtils.mkdir_p(code_b)

    seed_session(session_id: Bridge.session_key(session, "201"), intent_id: "201", cwd: code_a)
    seed_session(session_id: Bridge.session_key(session, "202"), intent_id: "202", cwd: code_b)

    found = Bridge.discover_bridge(session: session, cwd: code_a, store_home: @home)
    assert_equal "201", found.dig("intent", "id")

    shared_checkout_file = File.join(@home, "repo", "lib", "app.rb")

    wt_reason = Bridge.worktree_gate_decision(found, shared_checkout_file, home: @home)
    refute_nil wt_reason, "editing the shared checkout while a worktree is provisioned must block"
    assert_includes wt_reason, "intent 201"
    refute_includes wt_reason, "intent 202"
    assert_includes wt_reason, code_a

    code_reason = Bridge.code_gate_decision(found, shared_checkout_file, home: @home)
    refute_nil code_reason, "pre-How auto-armed code edit must block"
    assert_includes code_reason, "intent 201"
    refute_includes code_reason, "intent 202"
  end

  # --- 4. purge keeps every own-session row ------------------------------------

  def test_purge_keeps_all_own_session_rows
    session = "purge-session"
    write_index_active(%w[201]) # 202 is now terminal (not Active)

    seed_session(session_id: Bridge.session_key(session, "201"), intent_id: "201", cwd: @dirA)
    seed_session(session_id: Bridge.session_key(session, "202"), intent_id: "202", cwd: @dirB) # own row, terminal intent
    seed_session(session_id: "foreign--202", intent_id: "202", cwd: @dirB)

    removed = Bridge.purge_done_bridges(session: session, store: @store)

    conn = Plastic::DB.connect(@home)
    assert Plastic::DB::Sessions.active_for(conn, session: Bridge.session_key(session, "201"), cwd: nil),
           "own row (Active intent) must survive"
    assert Plastic::DB::Sessions.active_for(conn, session: Bridge.session_key(session, "202"), cwd: nil),
           "own row (terminal intent) must survive: never reap the session's own family"
    refute Plastic::DB::Sessions.active_for(conn, session: "foreign--202", cwd: nil),
           "a foreign session's terminal row purges"
    assert_includes removed, "foreign--202"
  end

  # --- 5. cwd wins over the auto-preference for a guided sibling --------------
  # The spec criterion "cwd inside worktree A resolves bridge A" is
  # unconditional: it must hold even when A is a GUIDED delivery and a sibling B
  # is auto-armed.

  def test_cwd_worktree_beats_auto_preference_for_guided_sibling
    session = "mixed-session"
    code_a = File.join(@home, "repo", ".claude", "worktrees", "201--demo-a")
    code_b = File.join(@home, "repo", ".claude", "worktrees", "202--demo-b")
    FileUtils.mkdir_p(code_a)
    FileUtils.mkdir_p(code_b)

    seed_session(session_id: Bridge.session_key(session, "201"), intent_id: "201", cwd: code_a, auto: false)
    seed_session(session_id: Bridge.session_key(session, "202"), intent_id: "202", cwd: code_b, auto: true)

    found = Bridge.discover_bridge(session: session, cwd: code_a, store_home: @home)
    assert_equal "201", found.dig("intent", "id"),
                 "cwd inside guided sibling A's worktree must resolve A, not the auto sibling B"
  end
end
