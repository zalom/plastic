require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "stringio"
require_relative "../scripts/lib/bridge"
require_relative "../scripts/lib/worktree"
require_relative "../scripts/lib/db"

# End-to-end test (intent 52, cutover in intent 41): drives the real
# scripts/hook-code-gate with a DERIVED-KEY armed session present in an
# isolated store (PLASTIC_STORE_HOME), no session id present. Proves the gate
# engages off a session-less session row.
class CodeGateHookTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/hook-code-gate", __dir__)

  def setup
    @root = Dir.mktmpdir("code-gate-hook")
    @store = File.join(@root, "store")
    @intent_dir = File.join(@store, "52--demo")
    FileUtils.mkdir_p(@intent_dir)
    File.write(File.join(@intent_dir, "52--demo.md"), "## Intent\nDemo\n")
    File.write(File.join(@intent_dir, "spec.md"), "spec\n") # stage why, pre-How

    @project_file = File.join(@root, "code", "app.rb")
    FileUtils.mkdir_p(File.dirname(@project_file))
    File.write(@project_file, "puts 1\n")

    @saved_session = ENV["CLAUDE_CODE_SESSION_ID"]
    @saved_store_home = ENV["PLASTIC_STORE_HOME"]
    ENV.delete("CLAUDE_CODE_SESSION_ID")
    ENV["PLASTIC_STORE_HOME"] = @root

    # Neutralize the real provision (intent 108 hermeticity fix): unstubbed,
    # arm's provision would plant a store worktree in the LIVE ~/.plastic.
    @real_provision = Worktree.method(:provision)
    Worktree.define_singleton_method(:provision) { |d, *_a, **_kw| d }

    # Arm via the derived key (no session). This registers a session row in
    # @root's plastic.db. arm_auto prints a derived-key notice to stderr;
    # silence it for clean output.
    silence_stderr { Bridge.arm_auto(nil, intent_id: "52", intent_dir: @intent_dir, store: @store, name: "demo") }
  end

  def silence_stderr
    original = $stderr
    $stderr = StringIO.new
    yield
  ensure
    $stderr = original
  end

  def teardown
    FileUtils.rm_rf(@root)
    @saved_session.nil? ? ENV.delete("CLAUDE_CODE_SESSION_ID") : ENV["CLAUDE_CODE_SESSION_ID"] = @saved_session
    @saved_store_home.nil? ? ENV.delete("PLASTIC_STORE_HOME") : ENV["PLASTIC_STORE_HOME"] = @saved_store_home
    Worktree.define_singleton_method(:provision, @real_provision) if @real_provision
  end

  def run_hook(file_path)
    env = { "PLASTIC_STORE_HOME" => @root, "CLAUDE_CODE_SESSION_ID" => nil }
    out = IO.popen(env, ["ruby", SCRIPT, file_path], err: [:child, :out], &:read)
    [out, $?]
  end

  def test_blocks_project_code_pre_how_off_derived_key_session
    _out, status = run_hook(@project_file)
    assert_equal 2, status.exitstatus, "pre-How project edit should be blocked"
  end

  def test_allows_edit_inside_intent_dir
    _out, status = run_hook(File.join(@intent_dir, "plan.md"))
    assert_equal 0, status.exitstatus, "edit inside intent dir should be allowed"
  end

  def test_allows_edit_under_plastic_home
    # The ~/.plastic exemption keys off the real Dir.home; the file need not exist.
    under_plastic = File.join(Dir.home, ".plastic", "store", "INDEX.md")
    _out, status = run_hook(under_plastic)
    assert_equal 0, status.exitstatus, "edit under ~/.plastic should be allowed"
  end

  def test_ignores_a_second_foreign_session_row
    # A foreign session's row for an unrelated intent must not affect the
    # derived-key session's own gate: it still blocks project code.
    other_dir = File.join(@store, "99--other")
    FileUtils.mkdir_p(other_dir)
    conn = Plastic::DB.connect(@root)
    Plastic::DB::Sessions.register(conn, session_id: "foreign--99", host: "h", pid: 1,
                                    cwd: other_dir, active_intent_id: "99", auto: true, now: Time.now)
    _out, status = run_hook(@project_file)
    assert_equal 2, status.exitstatus, "foreign row ignored; gate still blocks"
  end
end
