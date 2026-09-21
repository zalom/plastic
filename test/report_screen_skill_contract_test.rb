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

  # Row 90 (test_intent_continuing_routes_to_report_screen) was retired by intent 372
  # (family 2): the intent-continuing skill moved into the `plastic continue` command,
  # which is code, not skill prose - see the lead's routing rewrite in a later pass.

  # Rows 91/92 (savepoint-note for both kinds, the D19 heading convention stated in
  # intent-executing/SKILL.md) were retired by intent 341 (G8, n1): the runner-driven executing
  # skill names only `step`, `status`, `answer`, and the D19 heading match is now code-only
  # (scripts/lib/outcome_report.rb's ReportScreen.matching_action_heading), not prose an
  # executor needs to read.

  # --- 1.9 (intent 341, G8, n1): the skill contract the report screens read still resolves
  # after the ceremony cut - the headings the tests above and tick_with_commit_contract_test.rb
  # anchor on by name.

  def test_contract_headings_present
    headings = {
      "skills/auto/SKILL.md" => ["## Why (the lead)", "## How (the lead), then the plan review",
                                  "## Exec (the executor)", "## Review by risk", "## Completion",
                                  "## Team"]
    }
    headings.each do |file, hs|
      text = read(file)
      hs.each { |h| assert_includes text, h, "#{file} lost the #{h} heading a report-screen contract anchors on" }
    end
  end

  # --- item 10 (owner ruling 2026-08-31): cross-harness by construction, not
  # by branching - one sentence in each place a screen is printed.

  def test_human_report_contract_states_cross_harness_neutrality
    text = read("skills/auto/references/human-report-contract.md")
    assert_includes text, "every harness"
    assert_includes text, "harness name"
  end

  # test_intent_continuing_states_cross_harness_neutrality was retired alongside row 90
  # above: intent-continuing/SKILL.md no longer exists.

  # The 317a S6c labeled-table teaching in intent-ending/SKILL.md ("| Row | What |",
  # "action-file heading") was retired by intent 341 (G8, n1): outcome.md is generated, never
  # hand-authored, so the skill no longer teaches a human author the table shape.

  # --- intent 322 S5: the contract names the owner-of-the-table rule ---------

  def test_outcome_template_names_the_owning_heading
    text = read("templates/outcome.md")
    assert_includes text, "owns the matrix table"
  end

  # The intent-executing/intent-ending "owns the matrix table" prose pins were retired by
  # intent 341 (G8, n1) alongside the labeled-table teaching above: the rule is enforced by
  # scripts/lib/outcome_report.rb, not restated for a human author any more.

  # --- intent 330, O4: an unnamed status ask routes to the session verb -------

  # O4.1/O4.2 (test_continuing_skill_routes_a_status_ask_to_the_session_verb,
  # test_continuing_skill_keeps_the_named_and_delay_routes) were retired alongside row 90:
  # intent-continuing/SKILL.md no longer exists.

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

  # O4.7 (test_continuing_skill_still_names_the_roster_verb) was retired alongside row 90:
  # intent-continuing/SKILL.md no longer exists.

  # --- intent 331b: the plan verb, the PRE-delivery report ---------------------

  def test_human_report_contract_names_the_plan_screen # P12
    text = read("skills/auto/references/human-report-contract.md")
    assert_includes text, "report-screen plan"
    assert_includes text, "pre-delivery"
    assert_includes text, "How boundary"
  end

  def test_changelog_names_the_plan_screen # P13
    # A cut moves the Unreleased bullets into one Released line, so the pin
    # reads the whole changelog: the intent id and the verb must appear somewhere.
    text = read("CHANGELOG.md")
    assert_includes text, "331b"
    assert_includes text, "report-screen plan"
  end

  # --- intent 331f: skills bound to reports (S2/S3) --------------------------

  # F1-F4 (test_continuing_project_route_prints_dashboard_first,
  # test_continuing_named_intent_prints_state, test_continuing_status_ask_prints_session,
  # test_continuing_roadmap_route_prints_roadmap_state) were retired alongside row 90:
  # intent-continuing/SKILL.md no longer exists.

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

  # F8/F9 (test_ending_prints_delivered, test_speccing_prints_plan) were retired by intent
  # 372 (family 2): `plastic intent end` and `plastic intent spec` are commands now, not
  # skill prose, so there is no SKILL.md text left for these to read.

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

  # F12 (test_executing_prints_state) was retired by intent 341 (G8, n1): the runner-driven
  # executing skill no longer prints report-screen state itself; the lead does, from the auto
  # skill's How/Exec/Completion steps.

  # skills/intent-continuing/SKILL.md, skills/intent-ending/SKILL.md and
  # skills/intent-speccing/SKILL.md dropped by intent 372 (family 2): all three moved into
  # commands; their files are gone.
  BOUND_SKILL_FILES = %w[
    skills/auto/SKILL.md
    skills/roadmap/SKILL.md
    skills/dashboard/SKILL.md
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
