require "minitest/autorun"

# Intent 317, D15/D17/D19: the skills print the report screens instead of
# prose, and instruct appending Review/Commit savepoint lines and the D19
# heading convention for future Proven-by matches.
class ReportScreenSkillContractTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)

  def read(rel)
    File.read(File.join(REPO, rel))
  end

  # --- row 87: auto/SKILL.md's How step names report-screen state; Completion
  # names report-screen delivered --------------------------------------------

  def test_auto_skill_names_report_screen_state_at_how
    text = read("skills/auto/SKILL.md")
    assert_includes text, "report-screen state"
  end

  def test_auto_skill_names_report_screen_delivered_at_completion
    text = read("skills/auto/SKILL.md")
    assert_includes text, "report-screen delivered"
  end

  # --- row 88: human-report-contract.md names the three screens and five
  # triggers (D15, ruling 3) ---------------------------------------------------

  def test_human_report_contract_names_the_three_screens_and_triggers
    text = read("skills/auto/references/human-report-contract.md")
    assert_includes text, "report-screen state"
    assert_includes text, "report-screen delivered"
    assert_includes text, "report-screen delay"
    assert_includes text, "verdict"
    assert_includes text, "merge"
    assert_includes text, "release"
  end

  # --- row 89: auto/SKILL.md stays at or under 300 lines -----------------------

  def test_auto_skill_stays_at_or_under_300_lines
    lines = read("skills/auto/SKILL.md").lines.length
    assert lines <= 300, "skills/auto/SKILL.md grew to #{lines} lines, over the 300-line cap"
  end

  # --- row 90: intent-continuing/SKILL.md routes to state/state --all/delay ---

  def test_intent_continuing_routes_to_report_screen
    text = read("skills/intent-continuing/SKILL.md")
    assert_includes text, "report-screen state"
    assert_includes text, "state --all"
    assert_includes text, "report-screen delay"
  end

  # --- row 91: intent-executing/SKILL.md names savepoint-note for both kinds ---

  def test_intent_executing_names_savepoint_note_for_both_kinds
    text = read("skills/intent-executing/SKILL.md")
    assert_includes text, "savepoint-note --kind Commit"
    assert_includes text, "savepoint-note --kind Review"
  end

  # --- row 92: the D19 heading convention is written into the executing skill -

  def test_intent_executing_states_the_d19_heading_convention
    text = read("skills/intent-executing/SKILL.md")
    assert_includes text, "standalone token"
  end
end
