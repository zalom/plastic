# frozen_string_literal: true

require_relative "../../../../../test_helper"
require_relative "../../../../../../scripts/lib/plastic/graph/retrieval/evidence/text"

class RetrievalEvidenceTextPlainTextTest < Plastic::TestCase
  def test_plain_text_keeps_every_character_with_its_line
    extraction = Plastic::Graph::Retrieval::Evidence::Text::PlainText.extract("  a\n\tb ")

    assert_equal ["  a\n\tb ", [1, 1, 1, 1, 2, 2, 2]], [extraction.body, extraction.lines]
  end
end
