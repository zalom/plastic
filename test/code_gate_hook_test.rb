require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "stringio"
require_relative "../scripts/lib/bridge"
require_relative "../scripts/lib/worktree"

# End-to-end test (intent 52): drives the real scripts/hook-code-gate with a
# DERIVED-KEY armed bridge present in an isolated PLASTIC_TMP, no session id present.
# Proves the gate engages off a session-less bridge and that a malformed
# session:null bridge in the same dir is ignored.
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

    @bridge_tmp = Dir.mktmpdir("code-gate-hook-tmp")
    @saved_session = ENV["CLAUDE_CODE_SESSION_ID"]
    @saved_plastic_tmp = ENV["PLASTIC_TMP"]
    ENV["PLASTIC_TMP"] = @bridge_tmp
    ENV.delete("CLAUDE_CODE_SESSION_ID")

    # Neutralize the real provision (intent 108 hermeticity fix): unstubbed,
    # arm's provision would plant a store worktree in the LIVE ~/.plastic.
    @real_provision = Worktree.method(:provision)
    Worktree.define_singleton_method(:provision) { |d, *_a, **_kw| d }

    # Arm via the derived key (no session). This writes the bridge into PLASTIC_TMP.
    # arm_auto prints a derived-key notice to stderr; silence it for clean output.
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
    FileUtils.rm_rf(@bridge_tmp)
    @saved_session.nil? ? ENV.delete("CLAUDE_CODE_SESSION_ID") : ENV["CLAUDE_CODE_SESSION_ID"] = @saved_session
    @saved_plastic_tmp.nil? ? ENV.delete("PLASTIC_TMP") : ENV["PLASTIC_TMP"] = @saved_plastic_tmp
    Worktree.define_singleton_method(:provision, @real_provision) if @real_provision
  end

  def run_hook(file_path)
    env = { "PLASTIC_TMP" => @bridge_tmp, "CLAUDE_CODE_SESSION_ID" => nil }
    out = IO.popen(env, ["ruby", SCRIPT, file_path], err: [:child, :out], &:read)
    [out, $?]
  end

  def test_blocks_project_code_pre_how_off_derived_key_bridge
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

  def test_ignores_malformed_null_session_bridge
    # A session:null bridge alongside the valid derived-key bridge must be skipped
    # (bridge_valid? rejects it), so the gate still blocks project code.
    File.write(
      File.join(@bridge_tmp, "plastic-.json"),
      JSON.generate("session" => nil, "intent" => { "id" => "99" }, "build" => { "auto" => true }),
    )
    _out, status = run_hook(@project_file)
    assert_equal 2, status.exitstatus, "malformed bridge ignored; gate still blocks"
  end
end
