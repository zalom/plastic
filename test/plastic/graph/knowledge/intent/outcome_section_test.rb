# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/graph/knowledge/intent/outcome_section"

class OutcomeSectionTest < Minitest::Test
  def add(body, line = "- b") = Plastic::Graph::Knowledge::Intent::OutcomeSection.for(body, "## Reports").add(line)

  def test_an_empty_outcome_gets_the_starter_and_the_section
    assert_equal "# Outcome\n\n## Reports\n\n- b\n", add(nil)
  end

  def test_a_missing_section_goes_at_the_end_after_one_blank_line
    assert_equal "# Outcome\n\nText\n\n## Reports\n\n- b\n", add("# Outcome\n\nText\n\n\n")
  end

  def test_a_line_goes_last_in_its_section_before_the_next_heading
    body = "# Outcome\n\n## Reports\n\n- a\n\n## Notes\n\n- n\n"

    assert_equal "# Outcome\n\n## Reports\n\n- a\n- b\n\n## Notes\n\n- n\n", add(body)
  end

  def test_a_line_goes_last_in_the_last_section
    assert_equal "# Outcome\n\n## Reports\n\n- a\n- b\n", add("# Outcome\n\n## Reports\n\n- a\n")
  end

  def test_an_empty_section_gets_a_blank_line_under_its_heading
    assert_equal "# Outcome\n\n## Reports\n\n- b\n", add("# Outcome\n\n## Reports\n")
  end
end
