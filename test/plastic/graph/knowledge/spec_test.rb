# frozen_string_literal: true

require_relative "../../../test_helper"

class KnowledgeSpecTest < Plastic::TestCase
  Spec = Plastic::Graph::Knowledge::Spec

  def setup
    super
    @intent = open_intent
  end

  def spec(body)
    write("#{@intent.dir}/spec.md", body)
    sync_up
    Spec.new(retrieval, "1")
  end

  def test_done_criteria_are_the_bullets_under_the_heading_without_their_boxes
    read = spec("# Spec\n\n## Done criteria\n- [ ] One\n* [x] Two\nnot a bullet\n\n## Notes\n- Other\n")

    assert_equal %w[One Two], read.done_criteria
  end

  def test_an_acceptance_heading_holds_the_criteria_too
    assert_equal ["It ships"], spec("### Acceptance Criteria\n- It ships\n").done_criteria
  end

  def test_a_section_of_only_none_counts_zero
    assert_empty spec("## Open questions\n- None\n").open_decisions
  end

  def test_open_decisions_are_the_bullets_under_open_questions
    assert_equal ["Which store?"], spec("## Open Questions\n- Which store?\n").open_decisions
  end

  def test_goal_lines_keep_plain_lines_and_strip_bullet_dashes
    assert_equal ["Make it fast", "Keep it small"], spec("## Goal\n\nMake it fast\n- Keep it small\n").goal_lines
  end

  def test_an_intent_with_no_spec_has_no_criteria_and_no_decisions
    read = Spec.new(retrieval, "1")

    assert_equal [[], [], []], [read.done_criteria, read.open_decisions, read.goal_lines]
  end

  def test_a_bullet_reads_nil_for_a_line_that_is_not_one
    assert_equal ["Done", nil], [Spec.bullet("- [X] Done "), Spec.bullet("Done")]
  end
end
