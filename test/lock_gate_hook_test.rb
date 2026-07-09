require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "stringio"
require_relative "../scripts/lib/bridge"
require_relative "../scripts/lib/worktree"

# End-to-end test (intent 96): drives the real scripts/hook-lock-gate. Proves the
# fail-CLOSED gate denies a no-lock write to an active intent's dir via the
# PreToolUse JSON deny contract at exit 0, and ALLOWS once this session (guided or
# headless derived-key) holds a live lock. Reads never reach it (matcher), and a
# not-yet-active intent stays writable so creation is never locked out.
class LockGateHookTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/hook-lock-gate", __dir__)

  def setup
    @root = Dir.mktmpdir("lock-gate-hook")
    @store = File.join(@root, "store")
    @intent_dir = File.join(@store, "96--demo")
    FileUtils.mkdir_p(@intent_dir)
    File.write(File.join(@intent_dir, "96--demo.md"), "## Intent\nDemo\n")
    @intent_file = File.join(@intent_dir, "plan.md")

    # A second intent dir that is NOT in ## Active (creation / pre-lock / What).
    @new_intent_dir = File.join(@store, "97--new")
    FileUtils.mkdir_p(@new_intent_dir)
    @new_intent_file = File.join(@new_intent_dir, "97--new.md")

    # INDEX.md lives at the PARENT of the store dir; only 96 is Active.
    File.write(File.join(@root, "INDEX.md"),
               "## Active\n- [96 — demo](96--demo/96--demo.md)\n\n## Future\n")

    @bridge_tmp = Dir.mktmpdir("lock-gate-hook-tmp")
    # A dedicated, empty $HOME for the child process (intent 128): the gate now
    # also scans a global store under Dir.home for solo-delivery detection, so
    # the child must never see the real ~/.plastic.
    @fake_home = Dir.mktmpdir("lock-gate-hook-home")
    @session = "test-#{Process.pid}-#{object_id}"
    @saved_session = ENV["CLAUDE_CODE_SESSION_ID"]
    @saved_plastic_tmp = ENV["PLASTIC_TMP"]
    ENV["PLASTIC_TMP"] = @bridge_tmp
    ENV.delete("CLAUDE_CODE_SESSION_ID")

    # Neutralize real worktree git ops so arming stays hermetic (no real git).
    @real_provision = Worktree.method(:provision)
    Worktree.define_singleton_method(:provision) { |d, *_a, **_kw| d }
  end

  def teardown
    FileUtils.rm_rf(@root)
    FileUtils.rm_rf(@bridge_tmp)
    FileUtils.rm_rf(@fake_home)
    @saved_session.nil? ? ENV.delete("CLAUDE_CODE_SESSION_ID") : ENV["CLAUDE_CODE_SESSION_ID"] = @saved_session
    @saved_plastic_tmp.nil? ? ENV.delete("PLASTIC_TMP") : ENV["PLASTIC_TMP"] = @saved_plastic_tmp
    Worktree.define_singleton_method(:provision, @real_provision) if @real_provision
  end

  def silence_stderr
    original = $stderr
    $stderr = StringIO.new
    yield
  ensure
    $stderr = original
  end

  # Run the real hook script in a child process. cwd defaults to the store so the
  # session-strict discover_bridge cwd filter resolves a bridge whose intent.store
  # overlaps cwd. session => CLAUDE_CODE_SESSION_ID for the child (nil = headless).
  def run_hook(file_path, session: nil, chdir: @store)
    env = { "PLASTIC_TMP" => @bridge_tmp, "CLAUDE_CODE_SESSION_ID" => session,
            "HOME" => @fake_home }
    out = IO.popen(env, ["ruby", SCRIPT, file_path], err: [:child, :out], chdir: chdir, &:read)
    [out, $?]
  end

  def denied?(out)
    parsed = JSON.parse(out)
    parsed.dig("hookSpecificOutput", "permissionDecision") == "deny"
  rescue JSON::ParserError
    false
  end

  # (a) NO bridge + mutating write to an active intent's lifecycle dir -> deny.
  def test_no_lock_write_to_active_intent_is_denied
    out, status = run_hook(@intent_file)
    assert_equal 0, status.exitstatus, "gate must never exit non-zero to block"
    assert denied?(out), "no-lock write to active intent must deny: #{out.inspect}"
    assert_includes out, "/plastic-intent-starting"
  end

  # (b) guided lock for THIS session + write to that intent's dir -> ALLOW.
  def test_guided_lock_this_session_allows
    silence_stderr do
      Bridge.arm_guided(@session, intent_id: "96", intent_dir: @intent_dir, store: @store, name: "demo")
    end
    out, status = run_hook(@intent_file, session: @session)
    assert_equal 0, status.exitstatus
    assert_empty out.strip, "a held guided lock must ALLOW (empty stdout): #{out.inspect}"
  end

  # (c) headless derived-key lock + write to that intent's dir -> ALLOW (criterion 7).
  def test_headless_derived_key_lock_allows
    silence_stderr do
      Bridge.arm_guided(nil, intent_id: "96", intent_dir: @intent_dir, store: @store, name: "demo")
    end
    out, status = run_hook(@intent_file, session: nil)
    assert_equal 0, status.exitstatus
    assert_empty out.strip, "a headless derived-key lock must ALLOW: #{out.inspect}"
  end

  # (d) NO bridge + write CREATING a new/not-yet-active intent file -> ALLOW (no lockout).
  def test_creating_not_yet_active_intent_allows
    out, status = run_hook(@new_intent_file)
    assert_equal 0, status.exitstatus
    assert_empty out.strip, "creating a not-yet-active intent must ALLOW: #{out.inspect}"
  end

  # (f) headless lone-armed-bridge for intent A + write to a DIFFERENT active intent B
  # -> deny. A lock on A must not authorize writes into B's dir (cross-intent guard).
  def test_lock_for_one_intent_does_not_allow_writes_to_another
    other_dir = File.join(@store, "98--other")
    FileUtils.mkdir_p(other_dir)
    # Both 96 and 98 are active; only 96 is armed/locked this session.
    File.write(File.join(@root, "INDEX.md"),
               "## Active\n- [96 — demo](96--demo/96--demo.md)\n" \
               "- [98 — other](98--other/98--other.md)\n\n## Future\n")
    silence_stderr do
      Bridge.arm_guided(nil, intent_id: "96", intent_dir: @intent_dir, store: @store, name: "demo")
    end
    # A genuine rival (intent 128): a second live session holds a FRESH lock
    # elsewhere in scope, so solo can never be positively confirmed and the
    # ordinary per-intent scoping (a lock on 96 does not authorize 98) stays
    # fail-closed, exactly as before this session existed.
    rival_dir = File.join(@store, "99--rival")
    FileUtils.mkdir_p(rival_dir)
    Lock.acquire(rival_dir, session: "rival-session")
    out, status = run_hook(File.join(other_dir, "plan.md"), session: nil)
    assert_equal 0, status.exitstatus, "gate must never exit non-zero to block"
    assert denied?(out), "a headless lock on 96 must deny writes to 98's dir: #{out.inspect}"
  end

  # (g) headless lone-armed-bridge for intent A + write to A's OWN dir -> ALLOW.
  def test_lock_for_intent_allows_writes_to_its_own_dir
    silence_stderr do
      Bridge.arm_guided(nil, intent_id: "96", intent_dir: @intent_dir, store: @store, name: "demo")
    end
    out, status = run_hook(@intent_file, session: nil)
    assert_equal 0, status.exitstatus
    assert_empty out.strip, "a lock for 96 must ALLOW writes to 96's own dir: #{out.inspect}"
  end

  # (e) a malformed session:null bridge alongside is ignored -> the gate still denies.
  def test_malformed_null_session_bridge_is_ignored
    File.write(
      File.join(@bridge_tmp, "plastic-.json"),
      JSON.generate("session" => nil, "intent" => { "id" => "96" }, "build" => { "auto" => false },
                    "lock" => { "owner_session" => "x", "pid" => Process.pid, "host" => Socket.gethostname }),
    )
    out, status = run_hook(@intent_file)
    assert_equal 0, status.exitstatus
    assert denied?(out), "malformed bridge ignored; gate still denies: #{out.inspect}"
  end
end
