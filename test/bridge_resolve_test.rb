require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "digest"
require_relative "../scripts/lib/bridge"
require_relative "../scripts/lib/db"

# Tests for session resolution, derived keys, intent-dir discovery, and the
# `sessions`-table-backed bridge discovery (intent 41 cutover, replacing the
# /tmp bridge scan added in intent 52/90/131).
class BridgeResolveTest < Minitest::Test
  def setup
    @store = Dir.mktmpdir("bridge-resolve-store")
    @intent_dir = File.join(@store, "52--demo")
    FileUtils.mkdir_p(@intent_dir)
    File.write(File.join(@intent_dir, "52--demo.md"), "## Intent\nDemo\n")
    @saved_code_env = ENV["CLAUDE_CODE_SESSION_ID"]
    # Clear so a real ambient session id cannot leak into a "no id" case.
    ENV.delete("CLAUDE_CODE_SESSION_ID")
    @saved_store_home = ENV["PLASTIC_STORE_HOME"]
    ENV.delete("PLASTIC_STORE_HOME")
  end

  def teardown
    FileUtils.rm_rf(@store)
    if @saved_code_env.nil?
      ENV.delete("CLAUDE_CODE_SESSION_ID")
    else
      ENV["CLAUDE_CODE_SESSION_ID"] = @saved_code_env
    end
    @saved_store_home.nil? ? ENV.delete("PLASTIC_STORE_HOME") : ENV["PLASTIC_STORE_HOME"] = @saved_store_home
  end

  # --- derive_key ------------------------------------------------------------

  def test_derive_key_is_deterministic_and_prefixed
    k1 = Bridge.derive_key(@store, "52")
    k2 = Bridge.derive_key(@store, "52")
    assert_equal k1, k2
    assert k1.start_with?("auto-")
    expected = "auto-" + Digest::SHA256.hexdigest("#{@store}/52")[0, 10]
    assert_equal expected, k1
  end

  def test_derive_key_differs_per_intent
    refute_equal Bridge.derive_key(@store, "52"), Bridge.derive_key(@store, "53")
  end

  # --- resolve_session -------------------------------------------------------

  def test_resolve_session_prefers_explicit
    ENV["CLAUDE_CODE_SESSION_ID"] = "from-env"
    assert_equal "explicit-id", Bridge.resolve_session("explicit-id", intent_id: "52", store: @store)
  end

  def test_resolve_session_falls_back_to_env
    ENV["CLAUDE_CODE_SESSION_ID"] = "from-env"
    assert_equal "from-env", Bridge.resolve_session(nil, intent_id: "52", store: @store)
  end

  def test_resolve_session_falls_back_to_derived_key
    ENV.delete("CLAUDE_CODE_SESSION_ID")
    assert_equal Bridge.derive_key(@store, "52"),
                 Bridge.resolve_session(nil, intent_id: "52", store: @store)
  end

  def test_resolve_session_treats_whitespace_as_empty
    ENV["CLAUDE_CODE_SESSION_ID"] = "   "
    assert_equal Bridge.derive_key(@store, "52"),
                 Bridge.resolve_session("  ", intent_id: "52", store: @store)
  end

  def test_resolve_session_never_empty
    ENV.delete("CLAUDE_CODE_SESSION_ID")
    refute_nil Bridge.resolve_session(nil, intent_id: "52", store: @store)
    refute_empty Bridge.resolve_session("", intent_id: "52", store: @store)
  end

  # --- CLAUDE_CODE_SESSION_ID fallback (intent 79) ---------------------------

  def test_resolve_session_falls_back_to_code_session_id
    ENV["CLAUDE_CODE_SESSION_ID"] = "real-id"
    assert_equal "real-id", Bridge.resolve_session(nil, intent_id: "52", store: @store)
  end

  def test_resolve_session_derives_only_when_both_blank
    ENV.delete("CLAUDE_CODE_SESSION_ID")
    assert_equal Bridge.derive_key(@store, "52"),
                 Bridge.resolve_session(nil, intent_id: "52", store: @store)
  end

  def test_resolve_session_code_session_treats_whitespace_as_empty
    ENV["CLAUDE_CODE_SESSION_ID"] = "   "
    assert_equal Bridge.derive_key(@store, "52"),
                 Bridge.resolve_session(nil, intent_id: "52", store: @store)
  end

  def test_arm_auto_keys_by_code_session_id
    ENV["CLAUDE_CODE_SESSION_ID"] = "real-id"
    # Neutralize the real provision (intent 108 hermeticity fix): unstubbed,
    # arm's provision would plant a store worktree in the LIVE ~/.plastic.
    real_provision = Worktree.method(:provision)
    Worktree.define_singleton_method(:provision) { |d, *_a, **_kw| d }
    begin
      data = Bridge.arm_auto(nil, intent_id: "52", intent_dir: @intent_dir,
                             store: @store, name: "demo")
      assert_equal "real-id", data["session"]
      conn = Plastic::DB.connect(File.dirname(@store))
      row = Plastic::DB::Sessions.active_for(conn, session: "real-id--52", cwd: nil)
      refute_nil row, "expected a session row keyed by the real code session id AND intent id"
    ensure
      Worktree.define_singleton_method(:provision, real_provision)
    end
  end

  # --- session_key -----------------------------------------------------------

  def test_session_key_joins_bare_session_and_intent_id
    assert_equal "sess--52", Bridge.session_key("sess", "52")
  end

  # --- intent_dir_for --------------------------------------------------------

  def test_intent_dir_for_finds_ancestor_store_dir
    real_store = File.join(@store, "store")
    intent = File.join(real_store, "52--demo")
    FileUtils.mkdir_p(File.join(intent, "actions"))
    target = File.join(intent, "actions", "x.md")
    assert_equal intent, Bridge.intent_dir_for(target)
  end

  def test_intent_dir_for_returns_nil_outside_store
    file = File.join(@store, "random", "file.rb")
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, "x")
    assert_nil Bridge.intent_dir_for(file)
  end

  # --- bridge_valid? ---------------------------------------------------------

  def test_bridge_valid_true_for_well_formed
    assert Bridge.bridge_valid?({ "session" => "s", "intent" => { "id" => "52" } })
  end

  def test_bridge_valid_false_cases
    refute Bridge.bridge_valid?(nil)
    refute Bridge.bridge_valid?("string")
    refute Bridge.bridge_valid?({ "session" => "", "intent" => {} })
    refute Bridge.bridge_valid?({ "session" => "s" })
    refute Bridge.bridge_valid?({ "session" => "s", "intent" => "x" })
  end

  # --- discover_bridge (sessions-table backed) --------------------------------

  def seed_session(store_home, session_id:, intent_id:, cwd:, auto: false, now: Time.now)
    FileUtils.mkdir_p(File.join(store_home, "store", "#{intent_id}--demo")) unless Bridge.blank?(intent_id)
    conn = Plastic::DB.connect(store_home)
    Plastic::DB::Sessions.register(conn, session_id: session_id, host: "h", pid: 1,
                                    cwd: cwd, active_intent_id: intent_id, auto: auto, now: now)
  end

  def test_discover_prefers_auto_session
    Dir.mktmpdir("db-store") do |home|
      seed_session(home, session_id: "a--52", intent_id: "52", cwd: @intent_dir, auto: false)
      seed_session(home, session_id: "b--52", intent_id: "52", cwd: @intent_dir, auto: true)
      found = Bridge.discover_bridge(session: nil, cwd: @intent_dir, store_home: home)
      # Both rows are for intent "52" (session filtering is off since session: nil);
      # active_for prefers the auto-armed row when cwd cannot disambiguate siblings
      # that share the same cwd.
      assert_equal true, found["build"]["auto"]
    end
  end

  def test_discover_returns_nil_when_no_candidates
    Dir.mktmpdir("db-store") { |home| assert_nil Bridge.discover_bridge(session: nil, cwd: @store, store_home: home) }
  end

  def test_discover_returns_nil_for_foreign_session_when_caller_has_session
    Dir.mktmpdir("db-store") do |home|
      seed_session(home, session_id: "B--52", intent_id: "52", cwd: @intent_dir, auto: true)
      found = Bridge.discover_bridge(session: "A", cwd: @intent_dir, store_home: home)
      assert_nil found, "a session with no own row must not inherit a foreign session's row"
    end
  end

  def test_discover_derived_key_headless_resolves_own
    Dir.mktmpdir("db-store") do |home|
      key = Bridge.derive_key(@store, "52")
      seed_session(home, session_id: Bridge.session_key(key, "52"), intent_id: "52", cwd: @intent_dir, auto: true)
      found = Bridge.discover_bridge(session: key, cwd: @intent_dir, store_home: home)
      # to_bridge_data strips the "--<intent_id>" suffix back off (the bare
      # key is what the JSON content's "session" field always carried, even
      # for a per-intent-keyed file).
      assert_equal key, found["session"]
    end
  end

  def test_discover_single_own_session_still_resolves
    Dir.mktmpdir("db-store") do |home|
      seed_session(home, session_id: "solo--52", intent_id: "52", cwd: @intent_dir, auto: true)
      found = Bridge.discover_bridge(session: "solo", cwd: @intent_dir, store_home: home)
      refute_nil found
      assert_equal "52", found.dig("intent", "id")
    end
  end

  def test_discover_uses_plastic_store_home_env_override
    Dir.mktmpdir("db-store") do |home|
      seed_session(home, session_id: "env-sess--52", intent_id: "52", cwd: @intent_dir, auto: true)
      ENV["PLASTIC_STORE_HOME"] = home
      found = Bridge.discover_bridge(session: "env-sess", cwd: "/somewhere/unrelated")
      refute_nil found, "PLASTIC_STORE_HOME must win over cwd-based store resolution"
      assert_equal "52", found.dig("intent", "id")
    end
  end

  def test_discover_returns_nil_when_db_unavailable
    ENV["PLASTIC_STORE_HOME"] = "/no/such/store/home/at/all"
    assert_nil Bridge.discover_bridge(session: "solo", cwd: @intent_dir)
  end

  # --- enclosing_worktree_dir (intent 168) -----------------------------------

  def test_enclosing_worktree_dir_finds_the_owning_worktree
    file = "/r/.claude/worktrees/301--demo-a/x/y.rb"
    assert_equal "/r/.claude/worktrees/301--demo-a", Bridge.enclosing_worktree_dir(file)
  end

  def test_enclosing_worktree_dir_nil_for_store_path
    assert_nil Bridge.enclosing_worktree_dir("/r/.plastic/store/301--demo-a/spec.md")
  end

  def test_enclosing_worktree_dir_nil_for_shared_checkout_path
    assert_nil Bridge.enclosing_worktree_dir("/r/lib/app.rb")
  end

  def test_enclosing_worktree_dir_nil_without_dashes_in_dirname
    assert_nil Bridge.enclosing_worktree_dir("/r/.claude/worktrees/README")
  end

  def test_enclosing_worktree_dir_nil_for_blank_input
    assert_nil Bridge.enclosing_worktree_dir(nil)
    assert_nil Bridge.enclosing_worktree_dir("")
    assert_nil Bridge.enclosing_worktree_dir("   ")
  end

  # --- discover_bridge(edited_path:) worktree-membership-first (intent 168,
  # ported to the sessions-table resolver: an owner is a session row whose
  # cwd IS the enclosing worktree dir) -----------------------------------------

  def test_discover_edited_path_resolves_worktree_owner_across_session_boundary
    Dir.mktmpdir("db-store") do |home|
      Dir.mktmpdir("repo-root") do |repo|
        w601 = File.join(repo, ".claude", "worktrees", "601--demo")
        w602 = File.join(repo, ".claude", "worktrees", "602--demo")
        FileUtils.mkdir_p(w601)
        FileUtils.mkdir_p(w602)
        seed_session(home, session_id: "X--601", intent_id: "601", cwd: w601)
        seed_session(home, session_id: "Y--602", intent_id: "602", cwd: w602)

        edited_path = File.join(w602, "app.rb")
        found = Bridge.discover_bridge(session: "X", cwd: edited_path,
                                       edited_path: edited_path, store_home: home)
        refute_nil found, "the owning session row must resolve"
        assert_equal "602", found.dig("intent", "id"),
          "the worktree owner (session Y) must win over the caller's own session (X)"
      end
    end
  end

  def test_discover_edited_path_no_owner_returns_nil_not_the_session_matched_sibling
    Dir.mktmpdir("db-store") do |home|
      Dir.mktmpdir("repo-root") do |repo|
        w601 = File.join(repo, ".claude", "worktrees", "601--demo")
        w602 = File.join(repo, ".claude", "worktrees", "602--demo")
        FileUtils.mkdir_p(w601)
        FileUtils.mkdir_p(w602) # no session row owns this one

        seed_session(home, session_id: "X--601", intent_id: "601", cwd: w601)

        edited_path = File.join(w602, "app.rb")
        found = Bridge.discover_bridge(session: "X", cwd: edited_path,
                                       edited_path: edited_path, store_home: home)
        assert_nil found,
          "a worktree-scoped edit with no owning candidate must resolve nil, " \
          "never the session-matched sibling 601"
      end
    end
  end

end
