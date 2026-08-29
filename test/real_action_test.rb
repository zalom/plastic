require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/bridge"

# Intent 133a: How is reached only with at least one REAL action file in actions/
# (non-.gitkeep, non-empty, non-sentinel) at every tier. These tests exercise the
# pure bridge helpers directly, so no hook or session resolution is needed.
class RealActionTest < Minitest::Test
  SENTINEL = Bridge::PLACEHOLDER_SENTINEL

  def setup
    @root = Dir.mktmpdir("action-gate")
    @intent_dir = File.join(@root, "133--demo")
    FileUtils.mkdir_p(File.join(@intent_dir, "actions"))
    File.write(File.join(@intent_dir, "133--demo.md"), "## Intent\nDemo\n\n## Context\nWhy\n")
    File.write(File.join(@intent_dir, "spec.md"), "# Spec\nreal\n")
    File.write(File.join(@intent_dir, "plan.md"), "# Plan\nreal\n")
    File.write(File.join(@intent_dir, "checklist.md"), "# Checklist\nreal\n")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def actions_dir
    File.join(@intent_dir, "actions")
  end

  def write_action(name, body)
    File.write(File.join(actions_dir, name), body)
  end

  # --- has_real_action? ------------------------------------------------------

  def test_no_actions_dir_is_not_real
    FileUtils.rm_rf(actions_dir)
    refute Bridge.has_real_action?(@intent_dir),
           "a missing actions/ dir has no real action (fail-open, no raise)"
  end

  def test_empty_actions_dir_is_not_real
    refute Bridge.has_real_action?(@intent_dir), "an empty actions/ dir has no real action"
  end

  def test_gitkeep_only_is_not_real
    write_action(".gitkeep", "")
    refute Bridge.has_real_action?(@intent_dir), ".gitkeep never counts as an action"
  end

  def test_empty_action_md_is_not_real
    write_action("ACTION_1.md", "")
    refute Bridge.has_real_action?(@intent_dir), "an empty *.md is not a real action"
  end

  def test_sentinel_action_md_is_not_real
    write_action("ACTION_1.md", "#{SENTINEL}\n\nplaceholder\n")
    refute Bridge.has_real_action?(@intent_dir), "a sentinel-only *.md is not a real action"
  end

  def test_real_action_md_is_real
    write_action("ACTION_1.md", "# Action 1\nreal steps\n")
    assert Bridge.has_real_action?(@intent_dir), "a non-empty non-sentinel *.md is a real action"
  end

  # --- derive_stage ----------------------------------------------------------

  def test_derive_stage_stays_how_when_actions_empty
    assert_equal "how", Bridge.derive_stage(@intent_dir)
  end

  def test_derive_stage_stays_how_with_gitkeep_only
    write_action(".gitkeep", "")
    assert_equal "how", Bridge.derive_stage(@intent_dir)
  end

  def test_derive_stage_reaches_exec_with_real_action
    write_action("ACTION_1.md", "# Action 1\nreal steps\n")
    assert_equal "exec", Bridge.derive_stage(@intent_dir)
  end

  # --- check_gate: checklist.md write path -----------------------------------

  # --- code_gate_decision ----------------------------------------------------

  def code_bridge
    {
      "build" => { "auto" => true },
      "intent" => { "id" => "133", "store" => @root, "dir" => "133--demo" },
    }
  end
end
