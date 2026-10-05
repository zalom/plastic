# frozen_string_literal: true

require_relative "../../../../../test_helper"
require_relative "../../../../../../scripts/lib/plastic/graph/retrieval/evidence/text"

class RetrievalEvidenceTextSourceLinesTest < Plastic::TestCase
  SourceLines = Plastic::Graph::Retrieval::Evidence::Text::SourceLines

  def test_each_character_carries_its_line_and_a_newline_ends_its_own
    assert_equal [1, 1, 1, 2, 2], SourceLines.for("ab\ncd")
  end

  def test_empty_text_has_no_lines
    assert_empty SourceLines.for("")
  end
end
