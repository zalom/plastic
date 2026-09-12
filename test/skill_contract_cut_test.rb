# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

# SkillContractCutTest (intent 341, G8, n1): the four lifecycle skills carry ceremony the
# runner made redundant. Creating writes the thought only, speccing says up front that it is
# optional, executing names only the runner's three verbs, ending generates outcome.md through
# `scripts/outcome-report` and never hand-writes it, and the retired "Done" alias names no
# disposition in these skill bodies any more. Static and hermetic: reads real repo files,
# writes nothing.
class SkillContractCutTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  LIFECYCLE_SKILLS = %w[
    skills/intent-creating/SKILL.md
    skills/intent-speccing/SKILL.md
    skills/intent-executing/SKILL.md
    skills/intent-ending/SKILL.md
    skills/auto/SKILL.md
  ].freeze

  def read(rel)
    File.read(File.join(ROOT, rel))
  end

  # --- 1.1: creating names new-intent and no spec step -----------------------

  def test_creating_names_new_intent_and_no_spec_step
    text = read("skills/intent-creating/SKILL.md")
    assert_match(/new-intent/, text, "creating must scaffold through new-intent")
    refute_match(/spec\.md/i, text,
      "creating must not describe a spec-writing step; speccing is a separate, optional skill")
  end

  # --- 1.2: speccing opens by saying it is optional --------------------------

  def test_speccing_first_line_says_optional
    text = read("skills/intent-speccing/SKILL.md")
    body = text.split(/^---\s*$/, 3)[2].to_s
    lines = body.lines.map(&:strip).reject(&:empty?)
    refute_nil lines[1], "expected a prose line right after the H1 heading"
    assert_match(/optional/i, lines[1],
      "speccing must open by saying it is optional, got: #{lines[1].inspect}")
  end

  # --- 1.3: executing names only step, status, answer ------------------------

  def test_executing_body_names_only_the_three_verbs
    text = read("skills/intent-executing/SKILL.md")
    %w[step status answer].each do |verb|
      assert_match(/`#{verb}`|^## #{verb}$/i, text, "executing must name the #{verb} verb")
    end
    refute_match(/plan review|plan-reviewer/i, text, "executing must not describe plan review any more")
    refute_match(/mode selection/i, text, "executing must not describe mode selection any more")
    refute_match(/inline workflow/i, text, "executing must not describe an inline workflow any more")
    refute_match(/subagent-driven workflow/i, text, "executing must not describe the old subagent workflow any more")
    refute_match(/superpowers/i, text, "executing must not describe superpowers delegation any more")
  end

  # --- 1.4: ending generates outcome.md through scripts/outcome-report -------

  def test_ending_generates_through_outcome_report
    text = read("skills/intent-ending/SKILL.md")
    assert_match(/scripts\/outcome-report|outcome_report/i, text)
    refute_match(/author outcome\.md yourself/i, text,
      "ending must never invite hand-writing outcome.md any more")
  end

  # --- 1.5: no skill body names the retired "Done" alias ---------------------

  def test_done_alias_absent_from_skills
    LIFECYCLE_SKILLS.each do |f|
      text = read(f)
      refute_match(/\bDone,\s*delivered\b/i, text,
        "#{f} must not list Done as a disposition alongside delivered/abandoned")
      refute_match(/mark (an |the )?intent\s+Done\b/i, text,
        "#{f} must not describe marking an intent Done")
    end
  end

  # --- 1.8: every lifecycle skill body stays under 300 lines -----------------

  def test_lifecycle_skill_bodies_under_three_hundred_lines
    LIFECYCLE_SKILLS.each do |f|
      lines = read(f).lines.length
      assert lines <= 300, "#{f} is #{lines} lines, over the 300-line cap"
    end
  end
end
