# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

# Intent 329 - a tick is two edits (mark the box `[x]`, move the line to `## Completed`),
# made in the same commit that lands the work. This contract test pins that wording in every
# place that states the rule: the canonical definition, the implementer prompt template, the
# executor and enforcer agent bodies, the auto skill's Exec and Completion gates, and
# docs/internals.md. String/section assertions only, no filesystem fixtures needed: these are
# real repo files, read directly.
class TickWithCommitContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SKILL = File.join(ROOT, "skills/intent-executing/SKILL.md")
  IMPLEMENTER_PROMPT = File.join(ROOT, "skills/intent-executing/implementer-prompt.md")
  EXECUTOR = File.join(ROOT, "agents/plastic-executor.md")
  ENFORCER = File.join(ROOT, "agents/plastic-enforcer.md")
  AUTO_SKILL = File.join(ROOT, "skills/auto/SKILL.md")
  INTERNALS = File.join(ROOT, "docs/internals.md")

  # Real em dash, built from its codepoint so this test file itself never carries a literal
  # em-dash character on an added line (the added-line em-dash diff guard scans test/ too;
  # only test/fixtures/ is exempt). Mirrors scripts/lib/verify_intent.rb's own EM_DASH constant.
  EM_DASH = "\u2014"

  # Markdown soft-wraps a paragraph across raw newlines; collapse all whitespace runs
  # (including those newlines) to a single space before substring-matching prose, so a wording
  # check does not depend on where a line happens to break.
  def squeeze(text) = text.gsub(/\s+/, " ")

  def section(body, heading)
    raw = body[/^#{Regexp.escape(heading)}\n(.*?)(?=\n#+ |\z)/m, 1] || ""
    squeeze(raw)
  end

  def body_of(path) = squeeze(File.read(path))

  # --- O1: skills/intent-executing/SKILL.md `## Tick-as-you-land` (M1, M2) ---------------

  def test_tick_as_you_land_marks_the_box_and_moves_the_line
    tick_section = section(File.read(SKILL), "## Tick-as-you-land")
    assert_includes tick_section, "mark the item's box `[x]`"
    assert_includes tick_section, "move its checklist item from `## In Progress` to `## Completed`"
  end

  def test_tick_as_you_land_says_the_box_is_what_progress_reads
    tick_section = section(File.read(SKILL), "## Tick-as-you-land")
    assert_includes tick_section, "Progress bar reads"
    assert_match(/box/i, tick_section)
  end

  # --- O2: implementer-prompt.md step 5 (M3, M4, M5, M6) --------------------------------

  def test_implementer_prompt_ties_the_tick_to_the_commit
    assert_includes body_of(IMPLEMENTER_PROMPT),
      "Commit after each logical unit of work, and in the same step tick the checklist item that unit lands"
  end

  def test_implementer_prompt_names_the_incomplete_condition
    assert_includes body_of(IMPLEMENTER_PROMPT), "A commit without its tick is incomplete."
  end

  def test_implementer_prompt_names_both_halves_of_a_tick
    assert_includes body_of(IMPLEMENTER_PROMPT), "mark its box `[x]` and move the line to `## Completed`"
  end

  # Intent 329 post-execution fix: the executor prompt every implementer actually reads must
  # itself require the savepoint `Commit` line, not just skills/intent-executing/SKILL.md.
  def test_implementer_prompt_requires_the_savepoint_commit_line
    assert_includes body_of(IMPLEMENTER_PROMPT),
      'scripts/savepoint-note <intent_dir> --kind Commit --text "<sha> <what it proves>"'
  end

  # D11, hard constraint: these five lines already carried em dashes before this intent's
  # edit (originally lines 20 and 34-40); the edit must never reflow or re-add them as added
  # lines. Pins them byte-for-byte by content, not by a line index the edit may shift.
  def test_implementer_prompt_keeps_its_existing_em_dash_lines_verbatim
    lines = File.readlines(IMPLEMENTER_PROMPT, chomp: true)
    find_line = ->(prefix) { lines.find { |l| l.start_with?(prefix) } }

    assert_equal "2. Implement exactly what the task specifies #{EM_DASH} nothing more, nothing less.",
                 find_line.call("2. Implement exactly what the task specifies")
    assert_equal "**DONE** #{EM_DASH} All steps completed, tests pass, code committed.",
                 find_line.call("**DONE**")
    assert_equal "**DONE_WITH_CONCERNS** #{EM_DASH} Completed but I noticed: [describe concerns].",
                 find_line.call("**DONE_WITH_CONCERNS**")
    assert_equal "**NEEDS_CONTEXT** #{EM_DASH} I need clarification on: [specific questions].",
                 find_line.call("**NEEDS_CONTEXT**")
    assert_equal "**BLOCKED** #{EM_DASH} Cannot proceed because: [describe blocker].",
                 find_line.call("**BLOCKED**")
  end

  # --- O3: agents/plastic-executor.md (M7, M8, M9, M10) ---------------------------------

  def test_executor_responsibility_ties_the_tick_to_the_commit
    body = section(File.read(EXECUTOR), "## Your Responsibilities")
    assert_includes body, "**Tick with the commit**"
    assert_includes body, "A commit without its tick is incomplete."
    refute_includes body, "check off `checklist.md` items as they complete"
  end

  def test_executor_report_requires_ticks_to_match_commits
    assert_includes section(File.read(EXECUTOR), "## Completion Report"),
      "checked / total must equal the items whose commits exist"
  end

  def test_executor_workflow_ticks_as_each_action_lands
    assert_includes section(File.read(EXECUTOR), "## How You Work"),
      "ticking its checklist item in the same commit that lands it"
  end

  # Intent 329 post-execution fix: the same requirement, named in the executor agent body
  # itself, so an executor that never opens the skill still sees it.
  def test_executor_requires_the_savepoint_commit_line
    assert_includes body_of(EXECUTOR),
      'scripts/savepoint-note <intent_dir> --kind Commit --text "<sha> <what it proves>"'
  end

  # D12, hard constraint: the frontmatter `description:` block feeds the context-budget
  # catalog ceiling and the Codex TOML `description` field; it must never be touched.
  def test_agent_frontmatter_descriptions_are_unchanged
    executor_front = File.readlines(EXECUTOR, chomp: true)[0..6].join("\n")
    assert_equal <<~FRONT.strip, executor_front
      ---
      name: plastic-executor
      description: |
        Use for the Exec stage in auto mode: commit the plan's tests red, implement
        the actions, check off the checklist, and drive the test suite green.
      model: sonnet
      ---
    FRONT

    enforcer_front = File.readlines(ENFORCER, chomp: true)[0..7].join("\n")
    assert_equal <<~FRONT.strip, enforcer_front
      ---
      name: plastic-enforcer
      description: |
        Use as the auto team's lead: it takes the intent, writes the Why and How
        record, has the plan reviewed before code, dispatches one executor, reviews
        by risk, and closes.
      model: opus
      ---
    FRONT
  end

  # --- O4: agents/plastic-enforcer.md (M11, M12) ----------------------------------------

  def test_enforcer_verifies_ticks_at_review_and_merge
    assert_includes section(File.read(ENFORCER), "## Your Responsibilities"),
      "you verify tick-versus-diff at the post-execution review and again before the merge"
  end

  def test_enforcer_treats_a_mismatch_as_a_finding
    assert_includes section(File.read(ENFORCER), "## Your Responsibilities"),
      "A mismatch is a review finding, not a cleanup you perform silently."
  end

  # --- O5: skills/auto/SKILL.md Exec step and Completion gate (M13, M14) ----------------

  def test_auto_exec_step_names_tick_versus_diff
    exec_section = section(File.read(AUTO_SKILL), "## Exec (the executor)")
    assert_includes exec_section, "verify tick-versus-diff against the diff"
    assert_includes exec_section, "A mismatch is a review finding"
  end

  def test_auto_completion_gate_checks_ticks_against_the_diff
    completion_section = section(File.read(AUTO_SKILL), "## Completion")
    assert_includes completion_section, "This is the merge gate"
    assert_includes completion_section, "verify tick-versus-diff against the diff"
  end

  # --- O7: docs/internals.md (M15) -------------------------------------------------------

  def test_internals_doc_names_the_tick_lag_warning
    body = body_of(INTERNALS)
    assert_includes body, "intent_ticks_lag"
    assert_match(/doctor scan includes/i, body)
  end
end
