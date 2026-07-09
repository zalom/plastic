require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "stringio"
require "open3"
require_relative "../scripts/lib/bridge"
require_relative "../scripts/lib/lock"
require_relative "../scripts/lib/worktree"

# End-to-end test (intent 111): drives the real scripts/hook-lock-gate to prove
# the SECOND, independent claim gate composes under the existing delivery-lock
# gate. The writing session already holds the delivery lock in every case here
# (Lock.acquire, no bridge needed), so only the claim gate is exercised.
class ClaimGateHookTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/hook-lock-gate", __dir__)

  def setup
    @root = Dir.mktmpdir("claim-gate-hook")
    @store = File.join(@root, "store")
    @intent_dir = File.join(@store, "96--demo")
    FileUtils.mkdir_p(@intent_dir)
    File.write(File.join(@intent_dir, "96--demo.md"), "## Intent\nDemo\n")
    @intent_file = File.join(@intent_dir, "plan.md")

    File.write(File.join(@root, "INDEX.md"),
               "## Active\n- [96 — demo](96--demo/96--demo.md)\n\n## Future\n")

    @bridge_tmp = Dir.mktmpdir("claim-gate-hook-tmp")
    @saved_session = ENV["CLAUDE_CODE_SESSION_ID"]
    @saved_plastic_tmp = ENV["PLASTIC_TMP"]
    ENV["PLASTIC_TMP"] = @bridge_tmp
    ENV.delete("CLAUDE_CODE_SESSION_ID")

    @real_provision = Worktree.method(:provision)
    Worktree.define_singleton_method(:provision) { |d, *_a, **_kw| d }
  end

  def teardown
    FileUtils.rm_rf(@root)
    FileUtils.rm_rf(@bridge_tmp)
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

  # Captures stdout and stderr SEPARATELY (unlike lock_gate_hook_test.rb, which
  # merges them): this test needs stderr alone to assert the fail-open
  # advisory without it polluting the deny-JSON check on stdout.
  def run_hook(file_path, session:)
    env = { "PLASTIC_TMP" => @bridge_tmp, "CLAUDE_CODE_SESSION_ID" => session }
    Open3.capture3(env, "ruby", SCRIPT, file_path)
  end

  def denied?(out)
    parsed = JSON.parse(out)
    parsed.dig("hookSpecificOutput", "permissionDecision") == "deny"
  rescue JSON::ParserError
    false
  end

  def hold_delivery_lock(session)
    silence_stderr { Lock.acquire(@intent_dir, session: session) }
  end

  # (AC7 dormancy) delivery lock held, no claim file at all -> ALLOW.
  def test_allows_when_no_claim_present
    hold_delivery_lock("sess-1")
    out, _err, status = run_hook(@intent_file, session: "sess-1")
    assert_equal 0, status.exitstatus
    assert_empty out.strip, "no claim on the artifact: gate must be dormant: #{out.inspect}"
  end

  # (AC1/AC2) delivery lock held by sess-1, but plan.md is FRESHLY claimed by
  # sess-2 -> DENY naming sess-2 and the artifact.
  def test_denies_write_to_foreign_fresh_claim
    hold_delivery_lock("sess-1")
    Claim.acquire_claim(@intent_dir, "plan.md", session: "sess-2")
    out, _err, status = run_hook(@intent_file, session: "sess-1")
    assert_equal 0, status.exitstatus, "gate must never exit non-zero to block"
    assert denied?(out), "foreign fresh claim must deny: #{out.inspect}"
    assert_includes out, "sess-2"
    assert_includes out, "plan.md"
  end

  # sess-1 holds BOTH the delivery lock and the plan.md claim -> ALLOW.
  def test_allows_when_session_holds_claim
    hold_delivery_lock("sess-1")
    Claim.acquire_claim(@intent_dir, "plan.md", session: "sess-1")
    out, _err, status = run_hook(@intent_file, session: "sess-1")
    assert_equal 0, status.exitstatus
    assert_empty out.strip, "session holds its own claim: must ALLOW: #{out.inspect}"
  end

  # (AC3) sess-2's claim on plan.md is STALE -> fail open: ALLOW, and the
  # yielded/stale condition is surfaced on stderr.
  def test_fail_open_allows_stale_claim
    hold_delivery_lock("sess-1")
    Claim.acquire_claim(@intent_dir, "plan.md", session: "sess-2")
    old = Time.now - (Lock::TTL_SECONDS + 100)
    FileUtils.touch(File.join(@intent_dir, ".claims", "plan.md.claim"), mtime: old)
    out, err, status = run_hook(@intent_file, session: "sess-1")
    assert_equal 0, status.exitstatus
    refute denied?(out), "a stale claim must fail OPEN, not deny: #{out.inspect}"
    refute_empty err.strip, "the fail-open condition must be surfaced on stderr"
  end
end
