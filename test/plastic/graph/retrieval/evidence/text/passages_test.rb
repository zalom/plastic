# frozen_string_literal: true

require_relative "../../../../../test_helper"
require_relative "../../../../../../scripts/lib/plastic/graph/retrieval/evidence/text"

class RetrievalEvidenceTextPassagesTest < Plastic::TestCase
  Text = Plastic::Graph::Retrieval::Evidence::Text

  def build(source) = Text::Passages.build(source)

  def test_short_text_is_one_passage_with_its_lines
    assert_equal [{ body: "a\nb", position: 1, line_start: 1, line_end: 2 }], build("a\nb")
  end

  def test_long_text_splits_into_passages_that_overlap
    passages = build("x" * 1700)

    assert_equal [[1, 1600], [2, 300]], passages.map { |passage| [passage[:position], passage[:body].length] }
  end

  def test_an_extraction_keeps_the_lines_it_was_given
    assert_equal [7, 7], build(Text::Extraction.new("ab", [7, 7])).first.values_at(:line_start, :line_end)
  end

  def test_empty_text_has_no_passages
    assert_empty build("")
  end
end
