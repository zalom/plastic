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
    assert_includes text, "savepoint-note"
    assert_includes text, "--kind Commit"
    assert_includes text, "--kind Review"
  end

  # --- row 92: the D19 heading convention is written into the executing skill -

  def test_intent_executing_states_the_d19_heading_convention
    text = read("skills/intent-executing/SKILL.md")
    assert_includes text, "standalone token"
  end

  # --- item 10 (owner ruling 2026-08-31): cross-harness by construction, not
  # by branching - one sentence in each place a screen is printed.

  def test_human_report_contract_states_cross_harness_neutrality
    text = read("skills/auto/references/human-report-contract.md")
    assert_includes text, "every harness"
    assert_includes text, "harness name"
  end

  def test_intent_continuing_states_cross_harness_neutrality
    text = read("skills/intent-continuing/SKILL.md")
    assert_includes text, "harness name"
  end

  # --- 317a S6 (matrix S6c): the ending skill, which drives the outcome
  # backfill, must teach the label convention the readers match on.

  def test_ending_skill_teaches_the_labeled_table_convention
    text = read("skills/intent-ending/SKILL.md")
    assert_includes text, "| Row | What |"
    assert_includes text, "action-file heading"
  end

  # --- intent 330, O4: an unnamed status ask routes to the session verb -------

  # O4.1
  def test_continuing_skill_routes_a_status_ask_to_the_session_verb
    text = read("skills/intent-continuing/SKILL.md")
    assert_includes text, "report-screen session"
  end

  # O4.2
  def test_continuing_skill_keeps_the_named_and_delay_routes
    text = read("skills/intent-continuing/SKILL.md")
    assert_includes text, "report-screen state <intent_dir>"
    assert_includes text, "report-screen delay"
  end

  # O4.3
  def test_auto_skill_names_the_session_verb
    text = read("skills/auto/SKILL.md")
    assert_includes text, "report-screen session"
  end

  # O4.5
  def test_human_report_contract_names_the_session_screen
    text = read("skills/auto/references/human-report-contract.md")
    assert_includes text, "report-screen session"
  end

  # O4.7: a shipped test already pins "state --all" as the roster-alone verb;
  # the session-verb rewrite must never drop that string.
  def test_continuing_skill_still_names_the_roster_verb
    text = read("skills/intent-continuing/SKILL.md")
    assert_includes text, "state --all"
  end

  # --- intent 331b: the plan verb, the PRE-delivery report ---------------------

  def test_human_report_contract_names_the_plan_screen # P12
    text = read("skills/auto/references/human-report-contract.md")
    assert_includes text, "report-screen plan"
    assert_includes text, "pre-delivery"
    assert_includes text, "How boundary"
  end

  def test_changelog_unreleased_names_the_plan_screen # P13
    text = read("CHANGELOG.md")
    unreleased = text.split(/^## Released/, 2).first
    assert_includes unreleased, "331b"
    assert_includes unreleased, "plan"
  end

  # --- intent 331f: skills bound to reports (S2/S3) --------------------------

  # F1
  def test_continuing_project_route_prints_dashboard_first
    text = read("skills/intent-continuing/SKILL.md")
    assert_includes text, "dashboard.rb project <slug> --screen"
  end

  # F2
  def test_continuing_named_intent_prints_state
    text = read("skills/intent-continuing/SKILL.md")
    assert_includes text, "report-screen state <intent_dir>"
  end

  # F3
  def test_continuing_status_ask_prints_session
    text = read("skills/intent-continuing/SKILL.md")
    assert_includes text, "report-screen session"
  end

  # F4
  def test_continuing_roadmap_route_prints_roadmap_state
    text = read("skills/intent-continuing/SKILL.md")
    assert_includes text, "report-screen roadmap <roadmap.md> state"
  end

  # F5
  def test_auto_prints_plan_before_executor
    text = read("skills/auto/SKILL.md")
    before_exec = text.split(/^## Exec/, 2).first
    assert_includes before_exec, "report-screen plan"
  end

  # F6
  def test_auto_prints_state_at_triggers
    text = read("skills/auto/SKILL.md")
    assert_includes text, "report-screen state"
    assert_includes text, "human-report-contract.md"
  end

  # F7
  def test_auto_prints_delivered_once
    text = read("skills/auto/SKILL.md")
    assert_equal 1, text.scan("report-screen delivered").length
  end

  # F8
  def test_ending_prints_delivered
    text = read("skills/intent-ending/SKILL.md")
    assert_includes text, "report-screen delivered <intent_dir>"
  end

  # F9
  def test_speccing_prints_plan
    text = read("skills/intent-speccing/SKILL.md")
    assert_includes text, "report-screen plan <intent_dir>"
  end

  # F10
  def test_roadmap_skill_prints_roadmap_screens
    text = read("skills/roadmap/SKILL.md")
    assert_includes text, "report-screen roadmap <roadmap.md> plan"
    assert_includes text, "report-screen roadmap <roadmap.md> state"
    assert_includes text, "report-screen roadmap <roadmap.md> delivered"
  end

  # F11
  def test_dashboard_skill_prints_screen
    text = read("skills/dashboard/SKILL.md")
    assert_includes text, "default surface on every invocation"
    assert_includes text, "dashboard.rb project <slug> --screen"
  end

  # F12
  def test_executing_prints_state
    text = read("skills/intent-executing/SKILL.md")
    assert_includes text, "report-screen state <intent_dir>"
    assert_includes text, "red commit"
    assert_includes text, "suite goes green"
  end

  BOUND_SKILL_FILES = %w[
    skills/intent-continuing/SKILL.md
    skills/auto/SKILL.md
    skills/intent-ending/SKILL.md
    skills/intent-speccing/SKILL.md
    skills/roadmap/SKILL.md
    skills/dashboard/SKILL.md
    skills/intent-executing/SKILL.md
  ].freeze

  # F13
  def test_bound_skills_carry_first_print_rule
    BOUND_SKILL_FILES.each do |f|
      text = read(f).gsub(/\s+/, " ")
      assert_includes text, "first characters of the reply", "#{f} lacks the no-fence rule"
    end
  end

  # F14
  def test_bound_skills_under_300_lines
    BOUND_SKILL_FILES.each do |f|
      lines = read(f).lines.length
      assert lines <= 300, "#{f} grew to #{lines} lines, over the 300-line cap"
    end
  end

  # F23
  def test_contract_states_column_vocabulary
    text = read("skills/auto/references/human-report-contract.md").gsub(/\s+/, " ")
    assert_includes text, "Graph ID"
    assert_includes text, "before its first colon"
  end
end
