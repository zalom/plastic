# frozen_string_literal: true

require_relative "../../../../../test_helper"
require_relative "../../../../../../scripts/lib/plastic/graph/retrieval/search/results"

class RetrievalSearchResultsFusionTest < Plastic::TestCase
  def fuse(limit, *rows) = Plastic::Graph::Retrieval::Search::Results::Fusion.new(rows, limit).call.map { |row| row.fetch("uri") }

  def row(uri, score) = { "uri" => uri, "rrf_score" => score }

  def test_rows_sort_by_score_highest_first
    assert_equal %w[b a], fuse(5, row("a", 0.1), row("b", 0.2))
  end

  def test_rows_with_one_score_sort_by_reference
    assert_equal %w[a b], fuse(5, row("b", 0.1), row("a", 0.1))
  end

  def test_the_limit_keeps_the_best_rows
    assert_equal %w[c], fuse(1, row("a", 0.1), row("c", 0.3))
  end
end
