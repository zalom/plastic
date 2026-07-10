# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/bridge"
require_relative "../scripts/lib/db"

# Intent 81: the PreToolUse savepoint trigger stamps the pre-stage `started`
# event, derived from the file path alone (no bridge, no session), and never
# blocks. Cutover intent 41 ACTION_11: the event lands in `savepoint_events`,
# not savepoint.md. Drive the real hook script as a subprocess for fidelity.
class SavepointPreHookTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/hook-savepoint-pre", __dir__)

  def setup
    @root = Dir.mktmpdir("savepoint-pre")
    @store = File.join(@root, "store")
    @intent_dir = File.join(@store, "81--x")
    FileUtils.mkdir_p(@intent_dir)
    File.write(File.join(@intent_dir, "81--x.md"), "## Intent\nx\n")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def run_hook(file_path)
    out = IO.popen([RbConfig.ruby, SCRIPT, file_path], err: [:child, :out], &:read)
    [out, $?]
  end

  def pairs
    conn = Plastic::DB.connect(@root)
    Plastic::DB::SavepointEvents.events_for(conn, "81").map { |e| [e["stage"], e["event_type"]] }
  end

  def test_pre_write_of_spec_stamps_why_started
    # spec.md does not exist yet (the pre-write moment).
    spec = File.join(@intent_dir, "spec.md")
    out, status = run_hook(spec)
    assert_equal 0, status.exitstatus, "hook must exit 0, got: #{out}"
    assert_includes pairs, ["Why", "started"]
  end

  def test_pre_write_of_plan_stamps_how_started
    plan = File.join(@intent_dir, "plan.md")
    _out, status = run_hook(plan)
    assert_equal 0, status.exitstatus
    assert_includes pairs, ["How", "started"]
  end

  def test_started_fires_for_sentinel_placeholder
    # A scaffolded placeholder spec is not a real stage file: stage is starting.
    File.write(File.join(@intent_dir, "spec.md"), "#{Bridge::PLACEHOLDER_SENTINEL}\n\nx\n")
    run_hook(File.join(@intent_dir, "spec.md"))
    assert_includes pairs, ["Why", "started"]
  end

  def test_no_started_once_artifact_is_real
    File.write(File.join(@intent_dir, "spec.md"), "# Real spec\nbody\n")
    run_hook(File.join(@intent_dir, "spec.md"))
    refute_includes pairs, ["Why", "started"]
  end

  def test_non_lifecycle_path_is_noop
    other = File.join(@intent_dir, "resources", "note.md")
    FileUtils.mkdir_p(File.dirname(other))
    File.write(other, "x\n")
    _out, status = run_hook(other)
    assert_equal 0, status.exitstatus
    assert_empty pairs
  end

  def test_path_outside_any_intent_dir_is_noop
    loose = File.join(@root, "loose.md")
    File.write(loose, "x\n")
    _out, status = run_hook(loose)
    assert_equal 0, status.exitstatus
  end

  def test_empty_arg_exits_zero
    out = IO.popen([RbConfig.ruby, SCRIPT, ""], err: [:child, :out], &:read)
    assert_equal 0, $?.exitstatus, out
  end
end
