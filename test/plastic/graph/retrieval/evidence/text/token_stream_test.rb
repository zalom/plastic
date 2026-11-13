# frozen_string_literal: true

require_relative "../../../../../test_helper"
require_relative "../../../../../../lib/plastic/graph/retrieval/evidence/text"

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

  def test_tokens_on_lines_one_two_and_forty_keep_those_lines
    source = "[a] x\n[b] y\n#{"\n" * 37}[c]"
    lines = stream(source).extract { "X" }.lines

    assert_equal [1, 40], [lines.first, lines.last]
    assert_includes lines, 2
  end

  def test_two_megabytes_with_twenty_thousand_tokens_are_tokenized_in_under_two_seconds
    source = "#{"a" * 92} [tag]\n" * 20_000
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    stream(source).extract { "X" }

    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 2
  end
end
