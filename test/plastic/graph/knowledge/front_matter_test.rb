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
end
