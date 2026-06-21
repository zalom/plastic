require "minitest/autorun"
require "tmpdir"
require "fileutils"

# agent-report (intent 74) is the deterministic fallback for the auto-mode report
# contract: when a dispatched agent returns no usable completion report, the
# enforcer runs it to synthesize one from the intent dir's filesystem state. These
# tests shell out to the script (the way the enforcer would) and assert it surfaces
# the intent id, name, stage, role, checklist progress, and outcome line, and that
# two runs over identical state are byte-identical.
class AgentReportTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/agent-report", __dir__)

  def setup
    @root = Dir.mktmpdir("agent-report")
    @intent_dir = File.join(@root, "store", "74--enforce-agent-reports")
    FileUtils.mkdir_p(@intent_dir)
    File.write(File.join(@intent_dir, "74--enforce-agent-reports.md"), <<~MD)
      ---
      id: "74"
      intent: Enforce agent completion reports
      sources: ["68"]
      chain: []
      created: 2026-06-20
      author: zlatko
      tags: [reporting]
      ---

      ## Intent
      Enforce reports.
    MD
    File.write(File.join(@intent_dir, "savepoint.md"),
               "2026-06-20T00:00:00Z  How  plan.md created\n")
    File.write(File.join(@intent_dir, "checklist.md"), <<~MD)
      # Checklist

      ## In Progress
      - [x] ACTION_1 done
      - [ ] ACTION_2 pending
      - [ ] ACTION_3 pending
    MD
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def run_script(*args)
    IO.popen(["ruby", SCRIPT, @intent_dir, *args], &:read)
  end

  def test_report_surfaces_intent_stage_role_and_checklist
    out = run_script("--role", "plastic-executor")

    assert_includes out, "74", "report must surface the intent id"
    assert_includes out, "Enforce agent completion reports", "report must surface the intent name"
    assert_includes out, "plan.md created", "report must surface the current stage (savepoint line)"
    assert_includes out, "plastic-executor", "report must surface the role"
    assert_includes out, "Checklist: 1/3", "report must count checklist checked/total"
    assert_includes out, "synthesized", "report must label itself a synthesized fallback"
  end

  def test_role_defaults_to_stage_when_absent
    out = run_script
    # No --role given: role falls back to the current stage label.
    assert_match(/Role: .*How/, out, "role must default to the derived/savepoint stage")
  end

  def test_checklist_na_without_checklist
    FileUtils.rm_f(File.join(@intent_dir, "checklist.md"))
    out = run_script("--role", "planner")
    assert_includes out, "Checklist: n/a", "missing checklist reports n/a, not 0/0"
  end

  def test_outcome_line_surfaced_when_present
    File.write(File.join(@intent_dir, "outcome.md"), <<~MD)
      # Outcome: Enforce agent completion reports

      ## Summary
      Shipped the report contract and the deterministic fallback.
    MD
    out = run_script("--role", "reviewer")
    assert_includes out, "Shipped the report contract and the deterministic fallback.",
                    "report must surface the outcome summary line when outcome.md exists"
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
