# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/bridge"

# Intent 81: the PreToolUse savepoint trigger appends the pre-stage `started`
# line, derived from the file path alone (no bridge, no session), and never
# blocks. Drive the real hook script as a subprocess for fidelity.
class SavepointPreHookTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/hook-savepoint-pre", __dir__)

  def setup
    @root = Dir.mktmpdir("savepoint-pre")
    @intent_dir = File.join(@root, "store", "81--x")
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

  def ledger
    f = File.join(@intent_dir, "savepoint.md")
    File.exist?(f) ? File.read(f) : ""
  end

  def test_pre_write_of_spec_appends_why_started
    # spec.md does not exist yet (the pre-write moment).
    spec = File.join(@intent_dir, "spec.md")
    out, status = run_hook(spec)
    assert_equal 0, status.exitstatus, "hook must exit 0, got: #{out}"
    assert_includes ledger, "Why  started"
  end

  def test_pre_write_of_plan_appends_how_started
    plan = File.join(@intent_dir, "plan.md")
    _out, status = run_hook(plan)
    assert_equal 0, status.exitstatus
    assert_includes ledger, "How  started"
  end

  def test_started_fires_for_sentinel_placeholder
    # A scaffolded placeholder spec is not a real stage file: stage is starting.
    File.write(File.join(@intent_dir, "spec.md"), "#{Bridge::PLACEHOLDER_SENTINEL}\n\nx\n")
    run_hook(File.join(@intent_dir, "spec.md"))
    assert_includes ledger, "Why  started"
  end

  def test_no_started_once_artifact_is_real
    File.write(File.join(@intent_dir, "spec.md"), "# Real spec\nbody\n")
    run_hook(File.join(@intent_dir, "spec.md"))
    refute_includes ledger, "Why  started"
  end

  def test_non_lifecycle_path_is_noop
    other = File.join(@intent_dir, "resources", "note.md")
    FileUtils.mkdir_p(File.dirname(other))
    File.write(other, "x\n")
    _out, status = run_hook(other)
    assert_equal 0, status.exitstatus
    assert_equal "", ledger
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
