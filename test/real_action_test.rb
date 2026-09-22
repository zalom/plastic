require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/savepoint"
require_relative "../scripts/lib/backfill_intent"
# Intent 133a: How is reached only with at least one REAL action file in actions/
# (non-.gitkeep, non-empty, non-sentinel) at every tier. These tests exercise the
# pure bridge helpers directly, so no hook or session resolution is needed.
#
# Intent 334 (G1, n6): the forward shim widens has_real_action? to nodes/ too
# (D10r/D15r) - an intent delivered as a node graph is exactly as real as one
# delivered as actions/*.md, and has_files/missing_for_stage name whichever
# directory actually exists rather than the literal "actions/" (review B3).
class RealActionTest < Minitest::Test
  SENTINEL = Savepoint::PLACEHOLDER_SENTINEL

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
    refute Savepoint.has_real_action?(@intent_dir),
           "a missing actions/ dir has no real action (fail-open, no raise)"
  end

  def test_empty_actions_dir_is_not_real
    refute Savepoint.has_real_action?(@intent_dir), "an empty actions/ dir has no real action"
  end

  def test_gitkeep_only_is_not_real
    write_action(".gitkeep", "")
    refute Savepoint.has_real_action?(@intent_dir), ".gitkeep never counts as an action"
  end

  def test_empty_action_md_is_not_real
    write_action("ACTION_1.md", "")
    refute Savepoint.has_real_action?(@intent_dir), "an empty *.md is not a real action"
  end

  def test_sentinel_action_md_is_not_real
    write_action("ACTION_1.md", "#{SENTINEL}\n\nplaceholder\n")
    refute Savepoint.has_real_action?(@intent_dir), "a sentinel-only *.md is not a real action"
  end

  def test_real_action_md_is_real
    write_action("ACTION_1.md", "# Action 1\nreal steps\n")
    assert Savepoint.has_real_action?(@intent_dir), "a non-empty non-sentinel *.md is a real action"
  end

  # --- derive_stage ----------------------------------------------------------

  def test_derive_stage_stays_how_when_actions_empty
    assert_equal "how", Savepoint.derive_stage(@intent_dir)
  end

  def test_derive_stage_stays_how_with_gitkeep_only
    write_action(".gitkeep", "")
    assert_equal "how", Savepoint.derive_stage(@intent_dir)
  end

  def test_derive_stage_reaches_exec_with_real_action
    write_action("ACTION_1.md", "# Action 1\nreal steps\n")
    assert_equal "exec", Savepoint.derive_stage(@intent_dir)
  end

  # --- n6: nodes/ counts as a real action too (review: five globs, D15r) -------

  def test_nodes_dir_counts_as_a_real_action
    FileUtils.rm_rf(actions_dir)
    FileUtils.mkdir_p(File.join(@intent_dir, "nodes"))
    File.write(File.join(@intent_dir, "nodes", "n1.md"), "---\nnode: n1\nkind: work\n---\n# n1\nreal\n")
    assert Savepoint.has_real_action?(@intent_dir),
           "an intent with nodes/ and no actions/ must read as having a real action"
  end

  def test_has_files_names_the_directory_that_exists
    FileUtils.rm_rf(actions_dir)
    FileUtils.mkdir_p(File.join(@intent_dir, "nodes"))
    File.write(File.join(@intent_dir, "nodes", "n1.md"), "---\nnode: n1\nkind: work\n---\n# n1\nreal\n")
    files = Savepoint.has_files(@intent_dir)
    assert_includes files, "nodes/"
    refute_includes files, "actions/", "a nodes-only intent must never claim the literal actions/ artifact"
  end

  def test_backfill_skips_an_intent_that_has_nodes
    FileUtils.rm_rf(actions_dir)
    FileUtils.mkdir_p(File.join(@intent_dir, "nodes"))
    File.write(File.join(@intent_dir, "nodes", "n1.md"), "---\nnode: n1\nkind: work\n---\n# n1\nreal\n")
    result = BackfillIntent.classify(@intent_dir)
    refute_includes result[:targets], "actions/ACTION_1.md",
                     "a nodes-only intent already has real work; backfill must not invent actions/ACTION_1.md"
  end

  # --- n6 (post-execution review, non-blocking 4): missing_for_stage mirrors
  # has_real_files_in?'s actions-first order and real-file requirement -----

  def test_missing_for_stage_picks_actions_when_both_dirs_carry_real_files
    write_action("ACTION_1.md", "# Action 1\nreal steps\n")
    FileUtils.mkdir_p(File.join(@intent_dir, "nodes"))
    File.write(File.join(@intent_dir, "nodes", "n1.md"), "---\nnode: n1\nkind: work\n---\n# n1\nreal\n")
    missing = Savepoint.missing_for_stage("how", @intent_dir)
    assert_includes missing, "actions/",
                     "an intent with real files in both dirs must be told actions/, matching has_files' order"
    refute_includes missing, "nodes/"
  end

  def test_missing_for_stage_picks_actions_when_nodes_is_empty
    write_action("ACTION_1.md", "# Action 1\nreal steps\n")
    FileUtils.mkdir_p(File.join(@intent_dir, "nodes"))
    missing = Savepoint.missing_for_stage("how", @intent_dir)
    assert_includes missing, "actions/",
                     "an empty nodes/ dir must never win over a real actions/ file"
    refute_includes missing, "nodes/"
  end
end
