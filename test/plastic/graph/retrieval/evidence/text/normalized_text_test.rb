# frozen_string_literal: true

require_relative "../../../../../test_helper"
require_relative "../../../../../../scripts/lib/plastic/graph/retrieval/evidence/text"

class NormalizedTextTest < Minitest::Test
  def build(text_by_line)
    fragments = text_by_line.flat_map { |line, text| text.chars.map { |character| [character, line] } }
    Plastic::Graph::Retrieval::Evidence::Text::NormalizedText.new(fragments).build
  end

  def test_a_run_of_whitespace_becomes_one_space
    assert_equal "a b", build([[1, "a \t\n b"]]).body
  end

  def test_leading_and_trailing_whitespace_is_dropped
    assert_equal "a", build([[1, "  a  "]]).body
  end

  def test_each_character_keeps_its_source_line_and_a_space_keeps_the_line_it_started_on
    assert_equal [1, 1, 2], build([[1, "a "], [2, "b"]]).lines
  end
end
