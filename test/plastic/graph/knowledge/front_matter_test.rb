# frozen_string_literal: true

require_relative "../../../test_helper"

class KnowledgeFrontMatterTest < Plastic::TestCase
  FrontMatter = Plastic::Graph::Knowledge::FrontMatter

  def page(**fields) = "---\n#{fields.map { |name, value| "#{name}: #{value.to_json}" }.join("\n")}\n---\n"

  def test_a_field_with_an_escaped_quote_gives_the_quote
    assert_equal 'Open the "About" page', FrontMatter.fields(page(intent: 'Open the "About" page'))["intent"]
  end

  def test_a_field_with_an_escaped_backslash_and_a_quote_gives_both
    assert_equal 'a \\ "b" c', FrontMatter.fields(page(intent: 'a \\ "b" c'))["intent"]
  end

  def test_a_field_that_ends_in_an_escaped_quote_gives_the_quote
    assert_equal 'Say "hi"', FrontMatter.fields(page(intent: 'Say "hi"'))["intent"]
  end

  def test_a_field_with_no_quotes_gives_its_text
    assert_equal "plain", FrontMatter.fields("---\nintent: plain\n---\n")["intent"]
  end

  def test_a_single_quoted_field_gives_its_text_without_the_quotes
    assert_equal "24", FrontMatter.fields("---\nid: '24'\n---\n")["id"]
  end

  def test_a_doubled_single_quote_in_a_single_quoted_field_gives_one_quote
    assert_equal "it's done", FrontMatter.fields("---\nintent: 'it''s done'\n---\n")["intent"]
  end

  def test_a_double_quoted_field_that_is_not_a_json_string_gives_its_text_between_the_quotes
    assert_equal 'C:\\q drive', FrontMatter.fields("---\nintent: \"C:\\q drive\"\n---\n")["intent"]
  end
end
