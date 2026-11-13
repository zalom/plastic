# frozen_string_literal: true

require_relative "../../../../../test_helper"
require_relative "../../../../../../lib/plastic/graph/retrieval/evidence/text"

class RetrievalEvidenceTextSourceLinesTest < Plastic::TestCase
  SourceLines = Plastic::Graph::Retrieval::Evidence::Text::SourceLines

  TEXTS = [
    "",
    "a",
    "ab\ncd",
    "ab\ncd\n",
    "\n",
    "\n\n",
    "a\n\n\nb",
    "\na\n",
    "héllo\nwörld\n日本語\n",
    "no newline at all, only characters"
  ].freeze

  def test_a_line_ends_at_a_newline_and_a_trailing_newline_starts_no_line
    assert_equal [2, 2, 0, 1, 1], ["a\nb\n", "a\nb", "", "a", "\n"].map { |text| SourceLines.for(text).line_starts.length }
  end

  def test_the_empty_text_has_no_line_starts
    assert_empty SourceLines.for("").line_starts
  end

  def test_a_line_start_is_a_character_offset
    assert_equal [0, 3], SourceLines.for("éé\nx").line_starts
  end

  def test_a_text_of_many_lines_holds_one_start_per_line
    text = Array.new(500) { |index| "line #{index}" }.join("\n")

    assert_equal 500, SourceLines.for(text).line_starts.length
  end

  def test_every_slice_gives_the_first_and_last_line_the_per_character_list_gave
    TEXTS.each do |text|
      lines = SourceLines.for(text)
      (0..text.length + 1).each do |start|
        (0..text.length + 1).each do |length|
          assert_equal [edges(old_lines(text).slice(start, length))], [edges(lines.slice(start, length))],[text, start, length].inspect
        end
      end
    end
  end

  def test_a_slice_that_starts_past_the_end_gives_nothing
    assert_nil SourceLines.for("ab\ncd").slice(6, 1)
  end

  def test_a_slice_that_starts_at_the_end_is_empty
    answer = SourceLines.for("ab\ncd").slice(5, 3)

    assert_equal [nil, nil], [answer.first, answer.last]
  end

  def test_a_slice_past_the_end_of_the_text_ends_at_the_last_character
    answer = SourceLines.for("ab\ncd").slice(2, 40)

    assert_equal [1, 2], [answer.first, answer.last]
  end

  private

  def old_lines(text)
    line = 1
    text.each_char.map do |character|
      current = line
      line += 1 if character == "\n"
      current
    end
  end

  def edges(answer) = answer && [answer.first, answer.last]
end
