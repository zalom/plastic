require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require_relative "../scripts/lib/bridge"

# Regression test for intent 150: scripts/hook-code-gate resolved its bridge lookup
# against Dir.pwd (the hook process's own launch dir), never the file actually being
# edited. Under one session id owning two concurrent per-intent candidates, cwd never
# overlapped either one, so discovery fell through to the recency tiebreak and the
# newer sibling decided every edit in the session -- including edits that belonged
# to the OTHER sibling. This test fails against the pre-fix Dir.pwd line and passes
# once cwd is resolved from the edited file's own path (D1). Cutover intent 41: the
# candidates are `sessions` table rows (seeded through Plastic::DB::Sessions.register
# in an isolated PLASTIC_STORE_HOME), not /tmp bridge files.
class CodeGateHookCollisionTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/hook-code-gate", __dir__)

  def setup
    @tmp = Dir.mktmpdir("code-gate-collision-tmp")
    @home = Dir.mktmpdir("code-gate-collision-home")
    @store_home = File.join(@home, ".plastic", "projects", "demo")
    @store = File.join(@store_home, "store")
    FileUtils.mkdir_p(@store)

    @session = "collision-session"

    @dir_a = File.join(@store, "301--demo-a")
    @dir_b = File.join(@store, "302--demo-b")
    FileUtils.mkdir_p(@dir_a)
    FileUtils.mkdir_p(@dir_b)
    File.write(File.join(@dir_a, "301--demo-a.md"), "## Intent\nA\n")
    File.write(File.join(@dir_b, "302--demo-b.md"), "## Intent\nB\n")
    File.write(File.join(@dir_a, "spec.md"), "spec\n") # pre-How
    File.write(File.join(@dir_b, "spec.md"), "spec\n") # pre-How

    @code_a = File.join(@home, "repo-a", ".claude", "worktrees", "301--demo-a")
    @code_b = File.join(@home, "repo-b", ".claude", "worktrees", "302--demo-b")
    FileUtils.mkdir_p(@code_a)
    FileUtils.mkdir_p(@code_b)
    @file_a = File.join(@code_a, "app.rb")
    @file_b = File.join(@code_b, "app.rb")
    File.write(@file_a, "puts 1\n")
    File.write(@file_b, "puts 1\n")

    t = Time.now
    seed_session("301", @code_a, now: t)
    seed_session("302", @code_b, now: t + 2) # strictly newer than 301's

    # Unrelated to either worktree/store, proving the fix stops relying on Dir.pwd.
    @unrelated_cwd = Dir.mktmpdir("code-gate-collision-cwd")
  end

  def teardown
    FileUtils.rm_rf(@tmp)
    FileUtils.rm_rf(@home)
    FileUtils.rm_rf(@unrelated_cwd)
  end

  def seed_session(id, code, now:)
    conn = Plastic::DB.connect(@store_home)
    Plastic::DB::Sessions.register(conn, session_id: "#{@session}--#{id}", host: "h", pid: 1,
                                    cwd: code, active_intent_id: id, auto: true, now: now)
  end

  def run_hook(file_path, content = nil)
    env = { "PLASTIC_TMP" => @tmp, "HOME" => @home,
            "PLASTIC_STORE_HOME" => @store_home, "CLAUDE_CODE_SESSION_ID" => nil }
    args = [RbConfig.ruby, SCRIPT, file_path, @session]
    args << content if content
    Open3.capture3(env, *args, chdir: @unrelated_cwd)
  end

  def test_edit_inside_a_worktree_blocks_naming_301_not_302
    _out, err, status = run_hook(@file_a)
    assert_equal 2, status.exitstatus
    assert_includes err, "intent 301"
    refute_includes err, "intent 302"
  end

  def test_edit_inside_b_worktree_blocks_naming_302_not_301
    _out, err, status = run_hook(@file_b)
    assert_equal 2, status.exitstatus
    assert_includes err, "intent 302"
    refute_includes err, "intent 301"
  end

  def test_plastic_ok_escape_allows_and_audits
    log = File.join(@home, ".plastic", ".cache", "gate-escapes.log")
    refute File.exist?(log)
    _out, _err, status = run_hook(@file_a, "puts 1\n# plastic-ok\n")
    assert status.success?, "a plastic-ok edit must be allowed"
    assert File.exist?(log), "the escape must be audited"
    logged = File.read(log)
    assert_equal 1, logged.lines.length
    assert_includes logged, @session
    assert_includes logged, @file_a
  end

  def test_without_the_marker_still_blocks
    _out, err, status = run_hook(@file_a, "puts 1\n# not an escape\n")
    assert_equal 2, status.exitstatus
    assert_includes err, "intent 301"
  end
end
