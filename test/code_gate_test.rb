require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/bridge"
require_relative "../scripts/lib/db"

# Tests the PreToolUse code-edit gate decision (intent 27, R1).
class CodeGateTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("code-gate-home")
    @store = File.join(@home, ".plastic", "projects", "demo", "store")
    @intent_dir = File.join(@store, "27--demo")
    FileUtils.mkdir_p(@intent_dir)
    File.write(File.join(@intent_dir, "27--demo.md"), "## Intent\nDemo\n")
    File.write(File.join(@intent_dir, "spec.md"), "spec\n") # stage = why
    @project_file = File.join(@home, "code", "app.rb")
    FileUtils.mkdir_p(File.dirname(@project_file))
    File.write(@project_file, "puts 1\n")
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def bridge(auto:)
    {
      "intent" => { "id" => "27", "dir" => "27--demo", "store" => @store, "name" => "demo" },
      "build"  => { "auto" => auto },
    }
  end

  def decide(b, path)
    Bridge.code_gate_decision(b, path, home: @home)
  end

  def reach_how
    File.write(File.join(@intent_dir, "plan.md"), "plan\n")
    FileUtils.mkdir_p(File.join(@intent_dir, "actions"))
    File.write(File.join(@intent_dir, "checklist.md"), "- [ ] x\n")
  end

  def test_blocks_project_code_when_auto_and_pre_how
    refute_nil decide(bridge(auto: true), @project_file)
  end

  def test_allows_when_auto_false
    assert_nil decide(bridge(auto: false), @project_file)
  end

  def test_allows_when_no_bridge
    assert_nil decide(nil, @project_file)
  end

  def test_allows_edits_inside_intent_dir
    assert_nil decide(bridge(auto: true), File.join(@intent_dir, "spec.md"))
  end

  def test_allows_edits_under_plastic_home
    other = File.join(@home, ".plastic", "INDEX.md")
    assert_nil decide(bridge(auto: true), other)
  end

  def test_allows_once_how_reached
    reach_how
    assert_nil decide(bridge(auto: true), @project_file)
  end

  # --- AC5 (intent 128): solo delivery does NOT relax the stage-ordering gate -

  def test_solo_confirmed_lock_does_not_relax_the_stage_gate
    # A fresh, own delivery lock (the exact condition that relaxes the two
    # ARBITRATION gates) must have ZERO effect here: code_gate_decision does
    # not accept a session/lock/home argument at all and must stay
    # byte-for-byte unchanged. A pre-How project-code edit is still blocked.
    conn = Plastic::DB.connect(File.dirname(@store))
    Plastic::DB::Leases.acquire(conn, "27", session: "sess-1", host: "h")
    refute_nil decide(bridge(auto: true), @project_file),
               "solo delivery must never relax the stage-ordering gate"
  end
end
