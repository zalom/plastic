# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../scripts/lib/plastic/graph/retrieval/search/results"

class RetrievalSearchResultsTest < Plastic::TestCase
  def setup
    super
    open_intent("Shared words")
    row = { name: "store/1--a/x.bin", mode: 0o100644, mtime: 0, sz: 1, data: Plastic::Graph::SQL::Bytes.new("\x00".b), intent_id: "1", sha256: "h" }
    store_graphs.databases[:references].transaction { |batch| batch.put(:sqlar, row) }
  end

  def results(terms) = Plastic::Graph::Retrieval::Search::Results.new(@plastic_home, terms, excerpt: ->(body) { body }).call(["global"], 5)

  def test_the_matches_of_each_source_come_back_ranked
    assert_equal [["global", "1", 1]], results("shared").map { |row| row.values_at("store", "intent_id", "local_rank") }
  end

  def test_no_match_gives_no_results
    assert_empty results("absent")
  end

  def test_a_source_that_needs_maintenance_is_refused
    assert_raises(Plastic::Graph::RetrievalGraph::MaintenanceRequired) do
      Plastic::Graph::Retrieval::Search::Results.new(@plastic_home, "shared", excerpt: ->(body) { body }).call(["other"], 5)
    end
  end
end
