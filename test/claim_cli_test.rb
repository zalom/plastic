require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require_relative "../scripts/lib/db"
require_relative "../scripts/lib/bridge"

# plastic-lock claim/release-claim verbs + claims in status (intent 111 D5,
# AC2 via CLI, AC5; cutover intent 41 ACTION_10 onto the artifact grain of
# `lock_leases`). Hermetic: store in mktmpdir, explicit --intent-dir/--session
# (never ambient).
class ClaimCliTest < Minitest::Test
  CLI = File.expand_path("../scripts/plastic-lock", __dir__)

  def setup
    @home = Dir.mktmpdir("claim-cli-home")
    @store = File.join(@home, ".plastic", "projects", "demo", "store")
    @intent_dir = File.join(@store, "96--demo")
    FileUtils.mkdir_p(@intent_dir)
    File.write(File.join(@intent_dir, "96--demo.md"), "## Intent\nDemo\n")
    File.write(File.join(File.dirname(@store), "INDEX.md"),
               "## Active\n- [96 — demo](96--demo/96--demo.md)\n\n## Future\n")
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def store_home
    File.dirname(@store)
  end

  def conn
    Plastic::DB.connect(store_home)
  end

  def claim_current(artifact)
    Plastic::DB::Leases.current(conn, "96", artifact: artifact)
  end

  def cli(*args, session: "sess-1")
    Open3.capture3({ "CLAUDE_CODE_SESSION_ID" => nil },
                   RbConfig.ruby, CLI, *args,
                   "--intent-dir", @intent_dir, "--session", session)
  end

  def test_claim_acquires_and_exits_zero
    _out, _err, st = cli("claim", "--artifact", "plan.md", session: "sess-1")
    assert st.success?
    assert_equal "sess-1", claim_current("plan.md")["owner_session"]
  end

  def test_second_claim_same_session_is_rejected
    cli("claim", "--artifact", "plan.md", session: "sess-1")
    _out, err, st = cli("claim", "--artifact", "plan.md", session: "sess-1")
    refute st.success?
    assert_includes err, "sess-1"
    assert_includes err, "plan.md"
  end

  def test_second_claim_other_session_is_rejected
    cli("claim", "--artifact", "plan.md", session: "sess-1")
    _out, err, st = cli("claim", "--artifact", "plan.md", session: "sess-2")
    refute st.success?
    assert_includes err, "sess-1"
  end

  def test_claim_takes_over_expired_claim
    Plastic::DB::Leases.acquire(conn, "96", artifact: "plan.md", session: "old-sess", host: "h",
                                now: Time.now - Plastic::DB::Leases::TTL_SECONDS - 100)
    out, err, st = cli("claim", "--artifact", "plan.md", session: "sess-1")
    assert st.success?
    assert_equal "sess-1", claim_current("plan.md")["owner_session"]
    assert_includes(out + err, "took over")
  end

  def test_release_claim_frees_it
    cli("claim", "--artifact", "plan.md", session: "sess-1")
    _out, _err, st = cli("release-claim", "--artifact", "plan.md", session: "sess-1")
    assert st.success?
    assert_nil claim_current("plan.md")
  end

  def test_status_lists_live_claims
    Plastic::DB::Leases.acquire(conn, "96", artifact: "plan.md", session: "sess-1", host: "h")
    Plastic::DB::Leases.acquire(conn, "96", artifact: "spec.md", session: "sess-2", host: "h")
    out, _err, st = cli("status", session: "sess-1")
    assert st.success?
    report = JSON.parse(out)
    claims = report["claims"]
    refute_nil claims
    artifacts = claims.map { |c| c["artifact"] }
    assert_includes artifacts, "plan.md"
    assert_includes artifacts, "spec.md"
    plan = claims.find { |c| c["artifact"] == "plan.md" }
    assert_equal "sess-1", plan["owner_session"]
    assert_equal true, plan["fresh"]
  end
end
