# frozen_string_literal: true

require_relative "../../../../../test_helper"
require_relative "../../../../../../lib/plastic/graph/knowledge/repair/rebuild/plan_text"

# An old plan gives its steps, its approach and its decisions.
class RebuildPlanTextTest < Minitest::Test
  PlanText = Plastic::Graph::Knowledge::Repair::Rebuild::PlanText

  TEXT = <<~MD
    # Plan: Make it trustworthy

    ## Approach
    Default the doctor to the core tier.
    Keep the opt-in flag.

    ## Steps
    1. Change the signature
       of the runner.
    2. Add the flag.
    - [x] Step 3 - run the suite

    ## Decisions
    - Reversal of intent 56 is deliberate.
    - Keep the banner
      untouched.
  MD

  def test_numbered_and_ticked_lines_under_steps_are_steps
    assert_equal [["Change the signature of the runner.", false], ["Add the flag.", false], ["Step 3 - run the suite", true]],
      PlanText.new(TEXT).steps.map { |step| [step.title, step.done] }
  end

  def test_the_approach_is_one_paragraph
    assert_equal "Default the doctor to the core tier. Keep the opt-in flag.", PlanText.new(TEXT).approach
  end

  def test_each_bullet_of_decisions_is_one_decision
    assert_equal ["Reversal of intent 56 is deliberate.", "Keep the banner untouched."], PlanText.new(TEXT).decisions
  end

  def test_a_plan_with_no_such_section_gives_nothing
    plan = PlanText.new("# Plan\n\nNo implementation plan.\n")

    assert_equal [[], nil, []], [plan.steps, plan.approach, plan.decisions]
  end

  def test_a_plan_without_a_steps_heading_gives_its_numbered_lines
    assert_equal ["Search the messages.", "Review the tutorials."], PlanText.new("# Plan\n\n1. Search the messages.\n2. Review the tutorials.\n").steps.map(&:title)
  end

  def test_a_plan_with_no_approach_or_an_empty_one_gives_none
    assert_equal [nil, nil], ["# Plan\n", "# Plan\n\n## Approach\n\n## Steps\n1. a\n"].map { |text| PlanText.new(text).approach }
  end

  def test_an_indented_line_before_any_item_is_dropped
    assert_equal ["a"], PlanText.new("# Plan\n\n## Steps\n   stray\n1. a\n").steps.map(&:title)
  end
end
