require "minitest/autorun"
require "tmpdir"
require "fileutils"

# spawn-preamble (intent 4a1c1) emits a deterministic live-state preamble for a
# spawned agent, built purely from the intent dir's filesystem state. These tests
# shell out to the script (the way a harness dispatch wrapper would) and assert it
# surfaces the intent id, intent name, current stage, and the no-hallucinate
# instruction, and that two runs are byte-identical.
class SpawnPreambleTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/spawn-preamble", __dir__)

  def setup
    @root = Dir.mktmpdir("spawn-preamble")
    @intent_dir = File.join(@root, "store", "4a1c1--agent-harness")
    FileUtils.mkdir_p(@intent_dir)
    File.write(File.join(@intent_dir, "4a1c1--agent-harness.md"), <<~MD)
      ---
      id: 4a1c1
      intent: Agent harness foundation
      sources: ["4a1c1"]
      chain: ["4a1c1"]
      created: 2026-06-18
      author: zlatko
      tags: [harness]
      ---

      ## Intent
      Build the harness.
    MD
    File.write(File.join(@intent_dir, "savepoint.md"),
               "2026-06-18T00:00:00Z  Why  spec.md created\n")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def run_script(*args)
    IO.popen(["ruby", SCRIPT, @intent_dir, *args], &:read)
  end

  def test_preamble_contains_intent_id_name_stage_and_instruction
    out = run_script("--role", "plastic-planner")

    assert_includes out, "4a1c1", "preamble must surface the intent id"
    assert_includes out, "Agent harness foundation", "preamble must surface the intent name"
    assert_includes out, "spec.md created", "preamble must surface the current stage (savepoint line)"
    assert_includes out, "plastic-planner", "preamble must surface the role"
    assert_includes out,
      "do not hallucinate intents or stages",
      "preamble must carry the no-hallucinate honoring instruction"
  end

  # intent 74: every dispatched agent must be told to end with a structured
  # completion report. Assert the verbatim REPORT_CONTRACT wording is emitted, so
  # the contract doc and role prompts have a single source of truth to agree with.
  def test_preamble_carries_report_contract
    out = run_script("--role", "plastic-planner")

    assert_includes out,
      "END your turn with a structured completion report as your FINAL MESSAGE",
      "preamble must carry the mandatory completion-report contract"
    assert_includes out,
      "the planner explains the plan back to the orchestrator",
      "report contract must name the per-role payload exemplar"
    # Intent 84: reports are prose-stripped (envelope + payload only).
    assert_includes out, "prose-stripped",
      "report contract must instruct subagents to strip conversational prose"
    # Intent 82: the report carries an insights field; bg/dispatched agents
    # populate it and the orchestrator persists via insight-append.
    assert_includes out, "insights field",
      "report contract must name the insights field"
    assert_includes out, "scripts/insight-append",
      "report contract must name insight-append as the persist path"
  end

  def test_stage_derived_from_files_when_no_savepoint
    FileUtils.rm_f(File.join(@intent_dir, "savepoint.md"))
    File.write(File.join(@intent_dir, "spec.md"), "spec\n")
    out = run_script

    # spec.md present, no plan -> How stage derived from files.
    assert_includes out, "Current stage: How"
  end

  def test_deterministic_across_runs
    first = run_script("--role", "plastic-executor")
    second = run_script("--role", "plastic-executor")
    assert_equal first, second, "two runs over identical state must be byte-identical"
  end

  def test_usage_error_without_intent_dir
    out = IO.popen(["ruby", SCRIPT], err: [:child, :out], &:read)
    assert_includes out, "usage:"
    refute_equal 0, $?.exitstatus
  end
end
