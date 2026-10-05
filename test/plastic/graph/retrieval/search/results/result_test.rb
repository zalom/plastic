# frozen_string_literal: true

require_relative "../../../../../test_helper"
require_relative "../../../../../../scripts/lib/plastic/graph/retrieval/search/results"

class RetrievalSearchResultsResultTest < Plastic::TestCase
  Results = Plastic::Graph::Retrieval::Search::Results

  def setup
    super
    open_intent
    @row = retrieval.search("alpha").first
  end

  def result(rank: 2) = Results::Result.new(Results::Match.new(retrieval, "global", @row, rank, 60), excerpt: ->(body) { body[0, 3] }).to_h

  def test_a_result_names_its_store_rank_and_score
    assert_equal ["global", 2, 1.0 / 62], result.values_at("store", "local_rank", "rrf_score")
  end

  def test_a_result_carries_the_qualified_reference
    assert_equal retrieval.reference("1", @row.fetch("path")).fetch(:uri), result.fetch("uri")
  end

  def test_a_result_body_is_the_excerpt
    assert_equal @row.fetch("body")[0, 3], result.fetch("body")
  end

  def test_a_result_says_whether_its_intent_is_archived
    store_graphs.databases[:work].transaction { |batch| batch.put(:archives, { intent_id: "1", at: STAMP }) }

    assert result.fetch("archived")
  end
end
