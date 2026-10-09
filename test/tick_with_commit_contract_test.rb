# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

# A tick is two edits (mark the box `[x]`, move the line to `## Completed`),
# made in the same commit that lands the work. This contract test pins that wording in every
# place that states the rule: the executor and enforcer agent bodies, and docs/internals.md.
# String/section assertions only, no filesystem fixtures needed: these are real repo files,
# read directly.
#
# The rule's canonical statement lives in the agent bodies this file pins.
class TickWithCommitContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  EXECUTOR = File.join(ROOT, "agents/plastic-executor.md")
  ENFORCER = File.join(ROOT, "agents/plastic-enforcer.md")
  INTERNALS = File.join(ROOT, "docs/internals.md")

  # Markdown soft-wraps a paragraph across raw newlines; collapse all whitespace runs
  # (including those newlines) to a single space before substring-matching prose, so a wording
  # check does not depend on where a line happens to break.
  def squeeze(text) = text.gsub(/\s+/, " ")

  def section(body, heading)
    raw = body[/^#{Regexp.escape(heading)}\n(.*?)(?=\n#+ |\z)/m, 1] || ""
    squeeze(raw)
  end

  def body_of(path) = squeeze(File.read(path))

  # --- agents/plastic-executor.md ---------------------------------

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
      "recording `plastic node done ID NODE TEXT` with its findings once it lands"
  end

  # The same requirement is named in the executor agent body itself, so an executor
  # that never opens a skill still sees it.
  def test_executor_requires_the_savepoint_commit_line
    assert_includes body_of(EXECUTOR),
      'scripts/savepoint-note <intent_dir> --kind Commit --text "<sha> <what it proves>"'
  end

  # The frontmatter `description:` block feeds the context-budget
  # catalog ceiling and the Codex TOML `description` field; it must never be touched.
  def test_agent_frontmatter_descriptions_are_unchanged
    executor_front = File.readlines(EXECUTOR, chomp: true)[0..7].join("\n")
    assert_equal <<~FRONT.strip, executor_front
      ---
      name: plastic-executor
      description: |
        Use for the Exec stage in auto mode: commit the plan's tests red, implement
        the actions, check off the checklist, and drive the test suite green.
      model: sonnet
      effort: medium
      ---
    FRONT

    enforcer_front = File.readlines(ENFORCER, chomp: true)[0..8].join("\n")
    assert_equal <<~FRONT.strip, enforcer_front
      ---
      name: plastic-enforcer
      description: |
        Use as the auto team's lead: it takes the intent, writes the Why and How
        record, has the plan reviewed before code, dispatches one executor, reviews
        by risk, and closes.
      model: opus
      effort: medium
      ---
    FRONT
  end

  # --- agents/plastic-enforcer.md ----------------------------------------

  def test_enforcer_verifies_ticks_at_review_and_merge
    assert_includes section(File.read(ENFORCER), "## Your Responsibilities"),
      "you verify tick-versus-diff at the post-execution review and again before the merge"
  end

  def test_enforcer_treats_a_mismatch_as_a_finding
    assert_includes section(File.read(ENFORCER), "## Your Responsibilities"),
      "A mismatch is a review finding, not a cleanup you perform silently."
  end

  # --- docs/internals.md -------------------------------------------------------

  def test_internals_doc_names_the_tick_lag_warning
    body = body_of(INTERNALS)
    assert_includes body, "intent_ticks_lag"
    assert_match(/doctor scan includes/i, body)
  end
end
