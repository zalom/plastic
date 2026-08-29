# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "stringio"
require_relative "../scripts/lib/bridge"
require_relative "../scripts/lib/worktree"
require_relative "../scripts/lib/lock"

# Regression test for intent 131: two intents delivered concurrently under ONE
# session id used to clobber a single shared /tmp bridge file, so the LAST
# arm won and gates would resolve a sibling intent's bridge instead of the
# caller's own. The fix keys the bridge per intent
# (plastic-<session>--<intent_id>.json) and teaches discover_bridge to pick
# among a session's several bridges by cwd (worktree.code > intent dir >
# store), tolerating a legacy single-key file throughout.
#
# Hermetic: injected PLASTIC_TMP, ambient CLAUDE_CODE_SESSION_ID cleared,
# Worktree.provision/release stubbed (no real git).
class BridgeCollisionTest < Minitest::Test
  def setup
    @tmp = Dir.mktmpdir("bridge-collision-tmp")
    @saved_tmp = ENV["PLASTIC_TMP"]
    ENV["PLASTIC_TMP"] = @tmp
    @saved_session = ENV["CLAUDE_CODE_SESSION_ID"]
    ENV.delete("CLAUDE_CODE_SESSION_ID")

    @home = Dir.mktmpdir("bridge-collision-home")
    @store = File.join(@home, ".plastic", "projects", "demo", "store")
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
  end

  def teardown
    FileUtils.rm_rf(@tmp)
    FileUtils.rm_rf(@home)
    @saved_tmp.nil? ? ENV.delete("PLASTIC_TMP") : ENV["PLASTIC_TMP"] = @saved_tmp
    @saved_session.nil? ? ENV.delete("CLAUDE_CODE_SESSION_ID") : ENV["CLAUDE_CODE_SESSION_ID"] = @saved_session
    Worktree.define_singleton_method(:provision, @real_provision) if @real_provision
    Worktree.define_singleton_method(:release, @real_release) if @real_release
  end

  def write_index_active(ids)
    lines = ["## Active"]
    ids.each { |id| lines << "- [#{id} — demo](store/#{id}--demo/#{id}--demo.md)" }
    lines << ""
    lines << "## Future"
    File.write(File.join(File.dirname(@store), "INDEX.md"), lines.join("\n") + "\n")
  end

  def valid_bridge(session:, id:, dir:, code: nil, auto: true)
    {
      "session" => session,
      "intent" => { "id" => id, "dir" => File.basename(dir), "store" => @store, "name" => "demo #{id}" },
      "build" => { "auto" => auto },
      "worktree" => { "code" => code, "provisioned" => !code.nil? },
    }
  end

  # --- 1. path is per-intent keyed, with legacy fallback ---------------------

  def test_path_is_per_intent_keyed
    assert_equal "#{@tmp}/plastic-sess--201.json",
                 Bridge.path("sess", intent_id: "201", tmp: @tmp)
    assert_equal "#{@tmp}/plastic-sess.json", Bridge.path("sess", tmp: @tmp)
    assert_equal "#{@tmp}/plastic-sess.json", Bridge.path("sess", intent_id: nil, tmp: @tmp)
    assert_equal "#{@tmp}/plastic-sess.json", Bridge.path("sess", intent_id: "", tmp: @tmp)
  end

  # --- 2. two intents, one session, no clobber --------------------------------

  def test_two_intents_one_session_get_separate_files
    session = "shared-session"
    Bridge.arm_auto(session, intent_id: "201", intent_dir: @dirA, store: @store, name: "demo-a")
    Bridge.arm_auto(session, intent_id: "202", intent_dir: @dirB, store: @store, name: "demo-b")

    file_a = Bridge.path(session, intent_id: "201", tmp: @tmp)
    file_b = Bridge.path(session, intent_id: "202", tmp: @tmp)
    assert File.exist?(file_a), "intent A's bridge must exist"
    assert File.exist?(file_b), "intent B's bridge must exist"
    refute_equal file_a, file_b, "the two intents must not share one bridge file"

    data_a = JSON.parse(File.read(file_a))
    data_b = JSON.parse(File.read(file_b))
    assert_equal "201", data_a.dig("intent", "id"), "A's bridge must still carry A's id (no clobber)"
    assert_equal "202", data_b.dig("intent", "id"), "B's bridge must still carry B's id (no clobber)"
  end

  # --- 3. discover_bridge resolves by cwd/worktree.code -----------------------

  def test_discover_resolves_by_cwd_worktree
    session = "wt-session"
    code_a = File.join(@home, "repo", ".claude", "worktrees", "201--demo-a")
    code_b = File.join(@home, "repo", ".claude", "worktrees", "202--demo-b")
    FileUtils.mkdir_p(code_a)
    FileUtils.mkdir_p(code_b)

    File.write(File.join(@tmp, "plastic-#{session}--201.json"),
               JSON.generate(valid_bridge(session: session, id: "201", dir: @dirA, code: code_a)))
    sleep 0.02
    # B is written LAST (newest mtime), yet cwd inside A's worktree must still resolve A.
    File.write(File.join(@tmp, "plastic-#{session}--202.json"),
               JSON.generate(valid_bridge(session: session, id: "202", dir: @dirB, code: code_b)))

    found_a = Bridge.discover_bridge(session: session, cwd: code_a, tmp: @tmp)
    assert_equal "201", found_a.dig("intent", "id"),
                 "cwd inside A's worktree resolves to A even though B is newer"

    found_b = Bridge.discover_bridge(session: session, cwd: code_b, tmp: @tmp)
    assert_equal "202", found_b.dig("intent", "id"), "cwd inside B's worktree resolves to B"
  end

  # --- 4. gates resolve to the correct sibling --------------------------------

  def test_gates_resolve_to_correct_sibling
    session = "gate-session"
    code_a = File.join(@home, "repo", ".claude", "worktrees", "201--demo-a")
    code_b = File.join(@home, "repo", ".claude", "worktrees", "202--demo-b")
    FileUtils.mkdir_p(code_a)
    FileUtils.mkdir_p(code_b)

    File.write(File.join(@tmp, "plastic-#{session}--201.json"),
               JSON.generate(valid_bridge(session: session, id: "201", dir: @dirA, code: code_a)))
    File.write(File.join(@tmp, "plastic-#{session}--202.json"),
               JSON.generate(valid_bridge(session: session, id: "202", dir: @dirB, code: code_b)))

    found = Bridge.discover_bridge(session: session, cwd: code_a, tmp: @tmp)
    assert_equal "201", found.dig("intent", "id")

  end

  # --- 5. purge keeps every own-session bridge --------------------------------

  def test_purge_keeps_all_own_session_bridges
    session = "purge-session"
    write_index_active(%w[201]) # 202 is now terminal (not Active)

    own_a = File.join(@tmp, "plastic-#{session}--201.json")
    own_b = File.join(@tmp, "plastic-#{session}--202.json") # own bridge, terminal intent
    own_legacy = File.join(@tmp, "plastic-#{session}.json")
    File.write(own_a, JSON.generate(valid_bridge(session: session, id: "201", dir: @dirA)))
    File.write(own_b, JSON.generate(valid_bridge(session: session, id: "202", dir: @dirB)))
    File.write(own_legacy, JSON.generate(valid_bridge(session: session, id: "202", dir: @dirB)))

    foreign_terminal = File.join(@tmp, "plastic-foreign--202.json")
    File.write(foreign_terminal, JSON.generate(valid_bridge(session: "foreign", id: "202", dir: @dirB)))

    removed = Bridge.purge_done_bridges(session: session, tmp: @tmp)

    assert File.exist?(own_a), "own per-intent bridge (Active intent) must survive"
    assert File.exist?(own_b), "own per-intent bridge (terminal intent) must survive: never reap the session's own bridge"
    assert File.exist?(own_legacy), "own legacy bridge must survive"
    refute File.exist?(foreign_terminal), "a foreign session's terminal bridge purges"
    assert_includes removed, foreign_terminal
  end

  # --- 6. legacy single-key bridge is tolerated -------------------------------

  def test_legacy_single_key_is_tolerated
    session = "legacy-session"
    legacy_path = File.join(@tmp, "plastic-#{session}.json")
    File.write(legacy_path, JSON.generate(valid_bridge(session: session, id: "201", dir: @dirA)))

    read_data = Bridge.read(session, tmp: @tmp)
    refute_nil read_data, "read without an intent_id must still find the legacy file"
    assert_equal "201", read_data.dig("intent", "id")

    read_with_id = Bridge.read(session, intent_id: "201", tmp: @tmp)
    refute_nil read_with_id, "read with an intent_id falls back to the legacy file when no per-intent file exists"
    assert_equal "201", read_with_id.dig("intent", "id")

    found = Bridge.discover_bridge(session: session, cwd: @dirA, tmp: @tmp)
    refute_nil found, "discover_bridge must not crash on a legacy single-key file"
    assert_equal "201", found.dig("intent", "id")
  end

  # --- 7. cwd wins over the auto-preference for a guided sibling --------------
  # The spec criterion "cwd inside worktree A resolves bridge A" is
  # unconditional: it must hold even when A is a GUIDED delivery and a sibling B
  # is auto-armed. If the auto-preference pool were applied before cwd tiering,
  # cwd inside A's worktree would still resolve the auto sibling B (the exact
  # wrong-sibling class this intent fixes), so tiering runs on the full pool
  # first and cwd wins.

  def test_cwd_worktree_beats_auto_preference_for_guided_sibling
    session = "mixed-session"
    code_a = File.join(@home, "repo", ".claude", "worktrees", "201--demo-a")
    code_b = File.join(@home, "repo", ".claude", "worktrees", "202--demo-b")
    FileUtils.mkdir_p(code_a)
    FileUtils.mkdir_p(code_b)

    File.write(File.join(@tmp, "plastic-#{session}--201.json"),
               JSON.generate(valid_bridge(session: session, id: "201", dir: @dirA, code: code_a, auto: false)))
    File.write(File.join(@tmp, "plastic-#{session}--202.json"),
               JSON.generate(valid_bridge(session: session, id: "202", dir: @dirB, code: code_b, auto: true)))

    found = Bridge.discover_bridge(session: session, cwd: code_a, tmp: @tmp)
    assert_equal "201", found.dig("intent", "id"),
                 "cwd inside guided sibling A's worktree must resolve A, not the auto sibling B"
  end

  # --- 8. headless: a cwd store overlap still filters (tier 0 not inert) ------
  # No session (intent 52/90 degraded scan across sessions): two bridges in
  # DISJOINT stores. cwd inside store A must resolve A even when B (another
  # store) is newer, so a cwd store overlap keeps disambiguating off-cwd
  # foreign-store bridges rather than falling straight through to newest-mtime.

  def test_headless_cwd_store_beats_newer_foreign_store_bridge
    store_b = File.join(@home, ".plastic", "projects", "other", "store")
    FileUtils.mkdir_p(File.join(store_b, "301--other"))

    a = File.join(@tmp, "plastic-headA--201.json")
    b = File.join(@tmp, "plastic-headB--301.json")
    File.write(a, JSON.generate(valid_bridge(session: "headA", id: "201", dir: @dirA)))
    File.write(b, JSON.generate(
      "session" => "headB",
      "intent" => { "id" => "301", "dir" => "301--other", "store" => store_b, "name" => "other" },
      "build" => { "auto" => true },
      "worktree" => { "code" => nil, "provisioned" => false },
    ))
    File.utime(Time.now - 100, Time.now - 100, a)
    File.utime(Time.now, Time.now, b) # B newer: mtime alone would pick it

    found = Bridge.discover_bridge(session: nil, cwd: @store, tmp: @tmp)
    assert_equal "201", found.dig("intent", "id"),
                 "headless: cwd inside store A resolves A over a newer foreign-store bridge"
  end

  # --- 9. the legacy read fallback is intent-identity guarded -----------------
  # read(session, intent_id: A) may fall back to a legacy plastic-<session>.json
  # during the transition, but only when that file actually carries A. A caller
  # asking for A must never be handed a legacy file still holding sibling B,
  # since disarm_auto / plastic-lock release act on the returned bridge's
  # worktrees and lock.

  def test_legacy_read_fallback_guarded_by_intent_id
    session = "guard-session"
    File.write(File.join(@tmp, "plastic-#{session}.json"),
               JSON.generate(valid_bridge(session: session, id: "202", dir: @dirB)))

    assert_nil Bridge.read(session, intent_id: "201", tmp: @tmp),
               "read for 201 must not return a legacy file holding sibling 202"
    assert_equal "202", Bridge.read(session, intent_id: "202", tmp: @tmp)&.dig("intent", "id"),
                 "read for 202 still resolves the matching legacy file"
    assert_equal "202", Bridge.read(session, tmp: @tmp)&.dig("intent", "id"),
                 "read with no intent_id still tolerates the legacy file"
  end

  def capture_stderr
    original = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = original
  end

  # --- 10. intent 233: a two-sibling session refuses a no-id disarm ----------

  def test_no_id_disarm_on_a_two_sibling_session_touches_nothing
    session = "twin-session"
    Bridge.arm_auto(session, intent_id: "201", intent_dir: @dirA, store: @store, name: "demo-a")
    Bridge.arm_auto(session, intent_id: "202", intent_dir: @dirB, store: @store, name: "demo-b")

    assert File.exist?(Lock.path(@dirA))
    assert File.exist?(Lock.path(@dirB))

    # Plant the pre-131 legacy single-key bridge, carrying sibling A. Without
    # it a no-id disarm was ALREADY a no-op here (read returns nil when the
    # legacy file is absent), so the safety assertions below would pass against
    # the old code too and would prove nothing. With it, the old fall-through
    # picked A and released A's live lock. This is the case D6 exists for.
    File.write(Bridge.path(session, tmp: @tmp),
               File.read(Bridge.path(session, intent_id: "201", tmp: @tmp)))

    out = capture_stderr { @result = Bridge.disarm_auto(session) }

    assert_nil @result
    assert File.exist?(Lock.path(@dirA)), "sibling A's lock must survive a refused no-id disarm"
    assert File.exist?(Lock.path(@dirB)), "sibling B's lock must survive a refused no-id disarm"
    assert File.exist?(Bridge.path(session, intent_id: "201", tmp: @tmp))
    assert File.exist?(Bridge.path(session, intent_id: "202", tmp: @tmp))
    refute_empty out
    assert_includes out, session
  end

  def test_explicit_id_disarm_releases_only_the_named_sibling
    session = "twin-session-explicit"
    Bridge.arm_auto(session, intent_id: "201", intent_dir: @dirA, store: @store, name: "demo-a")
    Bridge.arm_auto(session, intent_id: "202", intent_dir: @dirB, store: @store, name: "demo-b")

    Bridge.disarm_auto(session, intent_id: "201")

    refute File.exist?(Lock.path(@dirA)), "201's lock must be released"
    assert File.exist?(Lock.path(@dirB)), "202's lock must be untouched"
    assert_equal "202", Bridge.read(session, intent_id: "202", tmp: @tmp)&.dig("intent", "id")
    assert_equal false, Bridge.read(session, intent_id: "201", tmp: @tmp)&.dig("build", "auto")
  end
end
