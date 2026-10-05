# frozen_string_literal: true

require_relative "../../../../../test_helper"
require_relative "../../../../../../scripts/lib/plastic/graph/retrieval/evidence/text"

class RetrievalEvidenceTextRichTextTest < Plastic::TestCase
  RichText = Plastic::Graph::Retrieval::Evidence::Text::RichText

  def body(source) = RichText.extract(source).body

  def test_control_words_and_braces_drop
    assert_equal "Rich text", body("{\\rtf1\\ansi Rich \\b text}")
  end

  def test_a_hex_escape_decodes_as_latin_one
    assert_equal "é", body("\\'e9")
  end

  def test_a_negative_unicode_escape_decodes_from_its_unsigned_value
    assert_equal "\u{FFFD}", body("\\u-3?")
  end

  def test_a_surrogate_pair_decodes_to_one_character
    assert_equal "😀", body("\\u55357?\\u56832?")
  end

  def test_a_lone_high_surrogate_stays_an_escape_for_the_tokenizer
    assert_equal "\\u55357?", RichText.resolve_pairs("\\u55357?")
  end

  def test_a_pair_that_is_not_adjacent_does_not_join
    assert_nil RichText.adjacent_pair(*[0, 9].map { |offset| /\\u(-?\d+)\?/.match("\\u55357? \\u56832?", offset) })
  end
end
