# frozen_string_literal: true

require_relative "../../../../../test_helper"
require_relative "../../../../../../lib/plastic/graph/retrieval/evidence/text"

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

  def by_offset(text)
    lines = Text::SourceLines.for(text)
    (0...text.length).step(1400).each_with_index.map do |offset, index|
      body = text[offset, 1600]
      slice = lines.slice(offset, body.length)
      { body:, position: index + 1, line_start: slice.first, line_end: slice.last }
    end
  end

  def test_ascii_text_gives_the_passages_cut_by_character_offset
    text = "line of ascii\n" * 700

    assert_equal by_offset(text), build(text)
  end

  def test_non_ascii_text_gives_the_passages_cut_by_character_offset
    text = "line — with é\n" * 700

    assert_equal by_offset(text), build(text)
  end

  def test_text_of_exactly_one_step_is_one_passage
    assert_equal by_offset("x" * 1400), build("x" * 1400)
  end

  def test_text_of_exactly_two_steps_gives_two_passages
    assert_equal by_offset("é" * 2800), build("é" * 2800)
  end

  def test_text_shorter_than_one_passage_is_cut_by_character_offset
    assert_equal by_offset("é—\nx"), build("é—\nx")
  end

  def test_four_hundred_thousand_lines_with_an_em_dash_each_are_split_in_under_two_seconds
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    build("dash — and some more text\n" * 400_000)

    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 2
  end
end
