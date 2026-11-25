# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/knowledge/spec_sections"

class SpecSectionsTest < Minitest::Test
  SECTIONS = Plastic::Graph::Knowledge::SpecSections
  WHOLE = "# Spec\n\n## Goal\n\nShip.\n\n## Done criteria\n\n- [c1] ships\n\n## Open decisions\n\nNone.\n\n## Constraints\n\n- none\n"

  def test_a_spec_with_every_section_has_no_problem
    assert_nil SECTIONS.problem(WHOLE)
  end

  def test_a_section_named_by_an_older_name_counts
    assert_empty SECTIONS.missing(WHOLE.sub("## Open decisions", "### Open Questions"))
  end

  def test_one_missing_section_is_named_alone
    assert_equal "the spec lacks the section Constraints; spec.md holds the sections Goal, Done criteria, Open decisions and Constraints",
      SECTIONS.problem(WHOLE.sub("## Constraints", "## Limits"))
  end

  def test_two_missing_sections_are_named_together
    assert_match(/\Athe spec lacks the sections Goal and Constraints;/, SECTIONS.problem(WHOLE.sub("## Goal", "").sub("## Constraints", "")))
  end

  def test_a_heading_word_inside_a_line_of_text_is_no_section
    assert_equal ["Goal"], SECTIONS.missing(WHOLE.sub("## Goal", "The Goal"))
  end
end
