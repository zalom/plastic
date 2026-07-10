require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/bridge"

# Tests for the placeholder sentinel + Bridge.stage_file_present? predicate and
# its integration with stage detection and the savepoint ledger (intent 60b).
class StageFilePresentTest < Minitest::Test
  SENTINEL = "<!-- plastic:placeholder -->".freeze

  def setup
    @dir = Dir.mktmpdir("stage-file-present")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def write(name, body)
    path = File.join(@dir, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
    path
  end

  # --- predicate -------------------------------------------------------------

  def test_false_for_missing_path
    refute Bridge.stage_file_present?(File.join(@dir, "nope.md"))
  end

  def test_false_for_sentinel_first_line
    path = write("spec.md", "#{SENTINEL}\n\nbody here\n")
    refute Bridge.stage_file_present?(path)
  end

  def test_true_for_real_file
    path = write("spec.md", "# Spec\n\nreal content\n")
    assert Bridge.stage_file_present?(path)
  end

  def test_true_for_partial_or_prefixed_sentinel_first_line
    # Exact first-line match only: a prefixed/partial sentinel reads as real.
    path = write("spec.md", "x #{SENTINEL}\n")
    assert Bridge.stage_file_present?(path)
    path2 = write("plan.md", "#{SENTINEL} trailing\n")
    assert Bridge.stage_file_present?(path2)
  end

  def test_empty_file_reads_as_present
    path = write("checklist.md", "")
    assert Bridge.stage_file_present?(path)
  end

  def test_reads_only_head_for_large_real_file
    big = "real first line\n" + ("x" * 5_000_000) + "\n"
    path = write("plan.md", big)
    assert Bridge.stage_file_present?(path)
  end

  # --- integration: scaffolded intent never advances past Why ----------------

  def scaffold_intent
    intent_dir = File.join(@dir, "60--demo")
    FileUtils.mkdir_p(File.join(intent_dir, "actions"))
    File.write(File.join(intent_dir, "60--demo.md"), "## Intent\nDemo\n\n## Context\nWhy\n")
    %w[spec.md plan.md checklist.md outcome.md].each do |f|
      File.write(File.join(intent_dir, f), "#{SENTINEL}\n\nplaceholder\n")
    end
    intent_dir
  end

  def test_scaffolded_intent_derive_stage_is_why_not_advanced
    intent_dir = scaffold_intent
    assert_equal "why", Bridge.derive_stage(intent_dir)
  end

  def test_scaffolded_intent_with_only_intent_file_is_why
    intent_dir = File.join(@dir, "61--bare")
    FileUtils.mkdir_p(intent_dir)
    File.write(File.join(intent_dir, "61--bare.md"), "## Intent\nDemo\n")
    assert_equal "why", Bridge.derive_stage(intent_dir)
  end

  def test_real_spec_advances_to_how
    intent_dir = scaffold_intent
    File.write(File.join(intent_dir, "spec.md"), "# Spec\nreal\n")
    assert_equal "how", Bridge.derive_stage(intent_dir)
  end

  def test_real_plan_and_checklist_stay_how_until_a_real_action_exists
    intent_dir = scaffold_intent
    File.write(File.join(intent_dir, "spec.md"), "# Spec\nreal\n")
    File.write(File.join(intent_dir, "plan.md"), "# Plan\nreal\n")
    File.write(File.join(intent_dir, "checklist.md"), "# Checklist\nreal\n")
    # Intent 133a: real plan + checklist but an empty actions/ does not reach Exec.
    assert_equal "how", Bridge.derive_stage(intent_dir)
    File.write(File.join(intent_dir, "actions", "ACTION_1.md"), "# Action 1\nreal\n")
    assert_equal "exec", Bridge.derive_stage(intent_dir)
  end

  def test_real_outcome_advances_to_done
    intent_dir = scaffold_intent
    File.write(File.join(intent_dir, "outcome.md"), "# Outcome\nreal\n")
    assert_equal "done", Bridge.derive_stage(intent_dir)
  end

  # --- integration: savepoint trio ignores sentinels ------------------------

  def test_rebuild_logs_only_what_for_scaffolded_intent
    intent_dir = scaffold_intent
    count = Bridge.rebuild_savepoint(intent_dir)
    assert_equal 1, count
    ledger = File.read(File.join(intent_dir, "savepoint.md"))
    assert_includes ledger, "What"
    refute_includes ledger, "spec.md created"
    refute_includes ledger, "outcome.md created"
  end

  def test_append_returns_false_for_sentinel_lifecycle_file
    intent_dir = scaffold_intent
    refute Bridge.append_savepoint(intent_dir, File.join(intent_dir, "plan.md"))
    refute File.exist?(File.join(intent_dir, "savepoint.md"))
  end

  def test_append_logs_real_lifecycle_file
    intent_dir = scaffold_intent
    File.write(File.join(intent_dir, "spec.md"), "# Spec\nreal\n")
    assert Bridge.append_savepoint(intent_dir, File.join(intent_dir, "spec.md"))
  end

  def test_code_gate_does_not_unlock_on_placeholder_plan_checklist
    intent_dir = scaffold_intent
    store = @dir
    bridge = {
      "build" => { "auto" => true },
      "intent" => { "id" => "60", "store" => store, "dir" => "60--demo" },
    }
    target = File.join(@dir, "project", "app.rb")
    refute_nil Bridge.code_gate_decision(bridge, target, home: @dir)

    File.write(File.join(intent_dir, "plan.md"), "# Plan\nreal\n")
    File.write(File.join(intent_dir, "checklist.md"), "# Checklist\nreal\n")
    # Intent 133a: real plan + checklist but an empty actions/ still blocks the gate.
    refute_nil Bridge.code_gate_decision(bridge, target, home: @dir)

    File.write(File.join(intent_dir, "actions", "ACTION_1.md"), "# Action 1\nreal\n")
    assert_nil Bridge.code_gate_decision(bridge, target, home: @dir)
  end
end
