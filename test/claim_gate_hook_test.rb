require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "stringio"
require "open3"
require_relative "../scripts/lib/bridge"
require_relative "../scripts/lib/db"
require_relative "../scripts/lib/worktree"

# End-to-end test (intent 111; cutover intent 41 ACTION_10): drives the real
# scripts/hook-lock-gate to prove the SECOND, independent claim gate composes
# under the existing delivery-lease gate. The writing session already holds
# the delivery lease in every case here, so only the claim gate is exercised.
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

    @saved_session = ENV["CLAUDE_CODE_SESSION_ID"]
    ENV.delete("CLAUDE_CODE_SESSION_ID")

    @real_provision = Worktree.method(:provision)
    Worktree.define_singleton_method(:provision) { |d, *_a, **_kw| d }
  end

  def teardown
    FileUtils.rm_rf(@root)
    @saved_session.nil? ? ENV.delete("CLAUDE_CODE_SESSION_ID") : ENV["CLAUDE_CODE_SESSION_ID"] = @saved_session
    Worktree.define_singleton_method(:provision, @real_provision) if @real_provision
  end

  def conn
    Plastic::DB.connect(@root)
  end

  def acquire_delivery(session)
    Plastic::DB::Leases.acquire(conn, "96", session: session, host: "h")
  end

  def acquire_claim(artifact, session:, now: Time.now)
    Plastic::DB::Leases.acquire(conn, "96", artifact: artifact, session: session, host: "h", now: now)
  end

  # Captures stdout and stderr SEPARATELY (unlike lock_gate_hook_test.rb, which
  # merges them): this test needs stderr alone to assert the fail-open
  # advisory without it polluting the deny-JSON check on stdout.
  def run_hook(file_path, session:)
    env = { "PLASTIC_STORE_HOME" => @root, "CLAUDE_CODE_SESSION_ID" => session }
    Open3.capture3(env, "ruby", SCRIPT, file_path)
  end

  def denied?(out)
    parsed = JSON.parse(out)
    parsed.dig("hookSpecificOutput", "permissionDecision") == "deny"
  rescue JSON::ParserError
    false
  end

  # (AC7 dormancy) delivery lease held, no claim at all -> ALLOW.
  def test_allows_when_no_claim_present
    acquire_delivery("sess-1")
    out, _err, status = run_hook(@intent_file, session: "sess-1")
    assert_equal 0, status.exitstatus
    assert_empty out.strip, "no claim on the artifact: gate must be dormant: #{out.inspect}"
  end

  # (AC1/AC2) delivery lease held by sess-1, but plan.md is FRESHLY claimed by
  # sess-2 -> DENY naming sess-2 and the artifact.
  def test_denies_write_to_foreign_fresh_claim
    acquire_delivery("sess-1")
    acquire_claim("plan.md", session: "sess-2")
    out, _err, status = run_hook(@intent_file, session: "sess-1")
    assert_equal 0, status.exitstatus, "gate must never exit non-zero to block"
    assert denied?(out), "foreign fresh claim must deny: #{out.inspect}"
    assert_includes out, "sess-2"
    assert_includes out, "plan.md"
  end

  # sess-1 holds BOTH the delivery lease and the plan.md claim -> ALLOW.
  def test_allows_when_session_holds_claim
    acquire_delivery("sess-1")
    acquire_claim("plan.md", session: "sess-1")
    out, _err, status = run_hook(@intent_file, session: "sess-1")
    assert_equal 0, status.exitstatus
    assert_empty out.strip, "session holds its own claim: must ALLOW: #{out.inspect}"
  end

  # (AC3) sess-2's claim on plan.md is EXPIRED -> fail open: ALLOW, and the
  # yielded/expired condition is surfaced on stderr.
  def test_fail_open_allows_expired_claim
    acquire_delivery("sess-1")
    acquire_claim("plan.md", session: "sess-2", now: Time.now - Plastic::DB::Leases::TTL_SECONDS - 100)
    out, err, status = run_hook(@intent_file, session: "sess-1")
    assert_equal 0, status.exitstatus
    refute denied?(out), "an expired claim must fail OPEN, not deny: #{out.inspect}"
    refute_empty err.strip, "the fail-open condition must be surfaced on stderr"
  end
end
