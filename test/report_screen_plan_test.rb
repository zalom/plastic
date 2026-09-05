require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "time"
require_relative "../scripts/lib/report_screen"

# Intent 331b: the plan screen, the PRE-delivery report - Asked, Decisions,
# Steps, Mode, Reviewer, then the Steps table (Step, Action, What) and the
# Risks table. Every cell traces to a file (D3/D14); a missing source prints
# "not recorded", or the D2 floor named on the Mode row, never a guess.
class ReportScreenPlanTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("report-screen-plan")
    @dir = File.join(@root, "12--slug")
    FileUtils.mkdir_p(File.join(@dir, "actions"))
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def write(name, body)
    path = File.join(@dir, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
  end

  def render
    template = File.read(File.expand_path("../templates/report-plan.md", __dir__))
    ReportScreen.render_plan(intent_dir: @dir, store_root: @root, template: template)
  end

  # --- P1: Asked, first sentence plus an ellipsis when more follows -----------

  def test_asked_is_first_sentence_with_ellipsis
    write("12--slug.md", <<~MD)
      ---
      id: "12"
      intent: "Demo intent"
      ---

      ## Intent
      Fix regressions, tests first. Then ship as alpha.5.
    MD
    assert_equal "Fix regressions, tests first…", ReportScreen.asked_first_sentence(@dir)
  end

  def test_asked_without_intent_section_is_not_recorded # P1a
    write("12--slug.md", "---\nid: \"12\"\n---\n\n## Context\nno intent section\n")
    assert_equal "not recorded", ReportScreen.asked_first_sentence(@dir)
  end

  # --- P2: Decisions falls back to the record on a placeholder spec -----------

  def test_decisions_fall_back_to_record
    write("spec.md", "<!-- plastic:placeholder -->\n# Spec\n")
    write("12--slug.md", <<~MD)
      ---
      id: "12"
      intent: "Demo intent"
      ---

      ## Intent
      Demo intent

      ### Decisions
      - D1 first
      - D2 second
    MD
    assert_equal "2 decisions in the intent record", ReportScreen.decision_note(@dir)
  end

  # --- P3: Steps counts only checklist items, never a bare bullet -------------

  def test_steps_count_only_s_items
    write("checklist.md", <<~MD)
      # Checklist

      - not a checklist item at all
      - [ ] S1 first step
      - [ ] S2 second step
    MD
    assert_equal 2, ReportScreen.plan_steps(@dir).length
  end

  # --- P4: Mode reads the live lock only, never outcome.md's frontmatter -----

  def test_mode_not_armed_without_lock
    assert_equal "not armed", ReportScreen.plan_mode(@dir)
  end

  def test_mode_reads_the_live_lock
    File.write(File.join(@dir, "delivery.lock"), { "owner_session" => "s", "run_mode" => "auto" }.to_json)
    assert_equal "auto", ReportScreen.plan_mode(@dir)
  end

  # --- P5: Reviewer takes the PLAN review line only ---------------------------

  def test_reviewer_uses_plan_review_line_only
    write("savepoint.md", <<~SP)
      2026-08-30T12:00:00Z  Review  plan review REVISE: two findings folded
      2026-08-30T13:00:00Z  Review  post-execution review FAIL: reproduced by the lead
    SP
    assert_equal "REVISE", ReportScreen.plan_reviewer(@dir)
  end

  def test_reviewer_recognizes_the_shipped_verdict_vocabulary # P5a
    write("savepoint.md", "2026-08-30T12:00:00Z  Review  plan review PROCEED: nothing folded\n")
    assert_equal "PROCEED", ReportScreen.plan_reviewer(@dir)
    write("savepoint.md", "2026-08-30T12:00:00Z  Review  plan review REVISE: one finding folded\n")
    assert_equal "REVISE", ReportScreen.plan_reviewer(@dir)
  end

  # P5b (post-execution review, finding A1): an intent re-reviewed after a
# REVISE carries TWO plan-review lines, and the newest is the live verdict.
# Without this row a regression from `.reverse.find` to `.find` would keep
# reporting the stale REVISE forever and no test would fail.
def test_reviewer_takes_the_last_plan_review_line # P5b
  write("savepoint.md", <<~SP)
    2026-08-30T12:00:00Z  Review  plan review REVISE: two findings folded
    2026-08-30T13:00:00Z  Review  post-execution review FAIL: reproduced by the lead
    2026-08-30T14:00:00Z  Review  plan review PROCEED: the findings are folded
  SP
  assert_equal "PROCEED", ReportScreen.plan_reviewer(@dir)
end

def test_reviewer_verdict_not_recorded_when_the_line_names_none # P5a
    write("savepoint.md", "2026-08-30T12:00:00Z  Review  plan review: no verdict word here\n")
    assert_equal "not recorded", ReportScreen.plan_reviewer(@dir)
  end

  def test_reviewer_not_reviewed_without_a_plan_review_line
    write("savepoint.md", "2026-08-30T12:00:00Z  Review  post-execution review FAIL: reproduced\n")
    assert_equal "not reviewed", ReportScreen.plan_reviewer(@dir)
  end

  # --- P6: Steps table Action column ------------------------------------------

  def test_step_without_action_prints_not_recorded
    write("actions/ACTION_1.md", "# ACTION_1\n\n## S2 - a different step\n\n| # |\n|---|\n| 1 |\n")
    assert_equal "not recorded", ReportScreen.action_file_for(@dir, "S1")
  end

  def test_step_with_headingless_matrix_prints_not_recorded # P6a
    write("actions/ACTION_1.md", "# ACTION_1\n\n## S1 - the step\n\nprose only, no matrix here\n")
    assert_equal "not recorded", ReportScreen.action_file_for(@dir, "S1")
  end

  def test_action_file_for_finds_the_matrix_bearing_heading
    write("actions/ACTION_1.md", "# ACTION_1\n\n## S1 - the step\n\n| # |\n|---|\n| 1 |\n")
    assert_equal "ACTION_1", ReportScreen.action_file_for(@dir, "S1")
  end

  # --- P6b: the step LABEL is the checklist's own, never positional ----------

  def test_plan_steps_keep_the_declared_label
    write("checklist.md", <<~MD)
      # Checklist

      ## Completed

      - [x] S6 sixth thing

      - [x] S1 first thing
      - [x] S3 third thing
    MD
    labels = ReportScreen.plan_steps(@dir).map { |s| s[:label] }
    assert_equal %w[S6 S1 S3], labels
  end

  def test_plan_steps_fall_back_to_positional_labels
    write("checklist.md", "# Checklist\n\n- [ ] finish the docs\n- [ ] S2 second thing\n")
    steps = ReportScreen.plan_steps(@dir)
    assert_equal "S1", steps[0][:label]
    assert_equal "finish the docs", steps[0][:text]
    assert_equal "S2", steps[1][:label]
  end

  # --- P7: Risks -----------------------------------------------------------------

  def test_risks_none_without_section
    assert_equal [], ReportScreen.risk_rows(@dir)
    write("plan.md", "# Plan\n\nno risks section here\n")
    assert_equal [], ReportScreen.risk_rows(@dir)
  end

  def test_risk_bullet_keeps_its_wrapped_continuation # P7a
    write("plan.md", <<~MD)
      # Plan

      ## Risks
      - The first risk wraps across
        a second physical line that belongs to it.
      - A second, unwrapped risk.
    MD
    rows = ReportScreen.risk_rows(@dir)
    assert_equal 2, rows.length
    assert_equal "The first risk wraps across a second physical line that belongs to it.", rows[0]
  end

  # --- P8: determinism -------------------------------------------------------------

  def test_render_plan_is_byte_identical
    write("12--slug.md", "---\nid: \"12\"\nintent: \"Demo\"\n---\n\n## Intent\nDemo.\n")
    write("checklist.md", "# Checklist\n\n- [ ] S1 do the thing\n")
    write("actions/ACTION_1.md", "# ACTION_1\n\n## S1 - do the thing\n\n| # |\n|---|\n| 1 |\n")
    write("plan.md", "# Plan\n\n## Risks\n- one risk\n")
    first = render
    second = render
    assert_equal first, second
  end

  # --- P9: escaping in Steps and Risks ----------------------------------------------

  def test_pipe_in_risk_is_escaped
    write("plan.md", "# Plan\n\n## Risks\n- a risk with a | pipe in it\n")
    out = render
    assert_includes out, "a risk with a \\| pipe in it"
  end

  # --- P9a: escaping in the field table ----------------------------------------------

  def test_pipe_in_asked_is_escaped
    write("12--slug.md", "---\nid: \"12\"\nintent: \"Demo\"\n---\n\n## Intent\nShip X | Y together.\n")
    out = render
    assert_includes out, "Ship X \\| Y together"
  end
end
