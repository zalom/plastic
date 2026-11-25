# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeLegacyDecisionBulletsTest < Plastic::TestCase
  def bullets(text) = Plastic::Graph::Knowledge::Legacy::DecisionBullets.call(text)

  def test_the_bullets_under_a_decisions_heading_are_read
    assert_equal ["D1 Ship it", "D2 Wait"], bullets("## Decisions\n- D1 Ship it\n- D2 Wait\n")
  end

  def test_bullets_in_a_nested_section_still_count
    assert_equal ["Ship it", "Nested"], bullets("## Decisions\n- Ship it\n### Detail\n- Nested\n")
  end

  def test_a_heading_at_the_same_level_ends_the_section
    assert_equal ["Ship it"], bullets("## Decisions\n- Ship it\n## Notes\n- Not a ruling\n")
  end

  def test_text_with_no_decisions_heading_has_no_bullets
    assert_empty bullets("## Notes\n- Not a ruling\n")
  end
end
