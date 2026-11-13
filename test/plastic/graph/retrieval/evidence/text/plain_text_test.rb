# frozen_string_literal: true

require_relative "../../../../../test_helper"
require_relative "../../../../../../lib/plastic/graph/retrieval/evidence/text"

class RetrievalEvidenceTextPlainTextTest < Plastic::TestCase
  def test_plain_text_keeps_every_character_with_its_line
    extraction = Plastic::Graph::Retrieval::Evidence::Text::PlainText.extract("  a\n\tb ")
    whole = extraction.lines.slice(0, extraction.body.length)

    assert_equal ["  a\n\tb ", 1, 2], [extraction.body, whole.first, whole.last]
  end

  def test_plain_text_keeps_one_start_for_each_line
    extraction = Plastic::Graph::Retrieval::Evidence::Text::PlainText.extract("  a\n\tb ")

    assert_equal [0, 4], extraction.lines.line_starts
  end
end
