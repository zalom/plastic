# frozen_string_literal: true

require_relative "../../../../../test_helper"
require_relative "../../../../../../scripts/lib/plastic/graph/retrieval/evidence/text"

class RetrievalEvidenceTextTokenStreamTest < Plastic::TestCase
  def stream(source) = Plastic::Graph::Retrieval::Evidence::Text::TokenStream.new(source, /\[\w+\]/)

  def test_each_match_is_replaced_by_the_block
    assert_equal "a X b", stream("a [tag] b").extract { "X" }.body
  end

  def test_the_block_sees_each_match
    seen = []
    stream("[one] [two]").extract { |match| seen << match[0] && "" }

    assert_equal %w[[one] [two]], seen
  end

  def test_text_with_no_match_passes_through
    assert_equal "plain", stream("plain").extract { "X" }.body
  end

  def test_a_replacement_carries_the_line_where_its_match_starts
    assert_equal 2, stream("a\n[tag]").extract { "X" }.lines.last
  end
end
