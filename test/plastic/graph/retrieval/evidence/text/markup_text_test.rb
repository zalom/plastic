# frozen_string_literal: true

require_relative "../../../../../test_helper"
require_relative "../../../../../../scripts/lib/plastic/graph/retrieval/evidence/text"

class RetrievalEvidenceTextMarkupTextTest < Plastic::TestCase
  MarkupText = Plastic::Graph::Retrieval::Evidence::Text::MarkupText

  def body(source) = MarkupText.extract(source).body

  def test_tags_become_spaces_between_words
    assert_equal "one two", body("<p>one</p><p>two</p>")
  end

  def test_scripts_and_styles_drop_with_their_content
    assert_equal "shown", body("<script>x()</script>shown<style>p{}</style>")
  end

  def test_entities_decode
    assert_equal "a & <b>", body("a &amp; &#60;b&#x3e;")
  end

  def test_the_kept_text_keeps_its_source_lines
    assert_equal [2, 2], MarkupText.extract("<p>\n</p>ab").lines.last(2)
  end
end
