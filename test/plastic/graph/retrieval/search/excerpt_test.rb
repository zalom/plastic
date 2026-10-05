# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../scripts/lib/plastic/graph/retrieval/search/excerpt"

class ExcerptTest < Minitest::Test
  EXCERPT = Plastic::Graph::Retrieval::Search::Excerpt

  def test_a_short_body_is_its_own_excerpt
    assert_equal "a short body", EXCERPT.new("short").call("a short body")
  end

  def test_a_long_body_centres_the_excerpt_on_the_match
    body = "#{"x" * 1000}needle#{"y" * 1000}"

    excerpt = EXCERPT.new("needle").call(body)

    assert_equal [320, 160], [excerpt.size, excerpt.index("needle")]
  end

  def test_a_match_ignores_case_and_accents
    body = "#{"x" * 1000}Café#{"y" * 1000}"

    assert_includes EXCERPT.new("cafe").call(body), "Café"
  end

  def test_no_match_starts_at_the_top
    assert_equal "a" * 320, EXCERPT.new("needle").call("a" * 1000)
  end
end
