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

  def test_an_outcome_of_blank_lines_only_gets_the_section_alone
    assert_equal "\n## Reports\n\n- b\n", add("\n\n")
  end
end

class OutcomeSectionLevelTest < Minitest::Test
  def add(body) = Plastic::Graph::Knowledge::Intent::OutcomeSection.for(body, "## Verification").add("- b")

  def test_a_section_of_another_level_and_case_takes_the_line
    assert_equal "# Outcome\n\n### verification\n\n- a\n- b\n\n## Notes\n", add("# Outcome\n\n### verification\n\n- a\n\n## Notes\n")
  end

  def test_a_deeper_heading_inside_the_section_stays_in_it
    assert_equal "# Outcome\n\n## Verification\n\n### Checks\n\n- a\n- b\n", add("# Outcome\n\n## Verification\n\n### Checks\n\n- a\n")
  end
end

class OutcomeSectionWithoutTest < Minitest::Test
  def without(body) = Plastic::Graph::Knowledge::Intent::OutcomeSection.for(body, "## Reports").without(["- b"])

  def test_the_section_keeps_its_other_lines
    assert_equal "# Outcome\n\n## Reports\n\n- a\n", without("# Outcome\n\n## Reports\n\n- a\n- b\n")
  end

  def test_a_section_left_empty_goes_with_its_heading
    assert_equal "# Outcome\n\nText\n\n## Notes\n\n- n\n", without("# Outcome\n\nText\n\n## Reports\n\n- b\n\n## Notes\n\n- n\n")
  end

  def test_an_outcome_that_was_only_the_section_is_left_empty
    assert_equal "\n", without("## Reports\n\n- b\n")
  end
end
