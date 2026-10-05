# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/search_query"
require_relative "../../../scripts/lib/plastic/graph/retrieval/evidence/writer"

class SearchQueryTest < Plastic::TestCase
  def setup
    super
    open_intent
    Plastic::Graph::Retrieval::Evidence::Writer.new(store_graphs.databases.fetch(:knowledge), origin).write("1", "evidence.md", "falcon wings")
    retrieval.backfill
  end

  def rows(limit: "5", terms: "falcon")
    context = call_context(harness: scoped_harness(slug: "global"), source_projects: [], terms:, limit:)
    Plastic::Workflows::SearchQuery.new(context).rows
  end

  def test_matching_passages_are_returned_with_their_store
    assert_includes rows.map { |row| row.fetch("path") }, "evidence.md"
  end

  def test_a_limit_out_of_range_is_a_usage_error
    error = assert_raises(Plastic::CLI::Command::Usage) { rows(limit: "0") }

    assert_equal "search limit must be between 1 and 100", error.message
  end

  def test_a_limit_that_is_not_a_number_is_a_usage_error
    error = assert_raises(Plastic::CLI::Command::Usage) { rows(limit: "many") }

    assert_equal "search limit must be an integer", error.message
  end
end
