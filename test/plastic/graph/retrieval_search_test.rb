# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/graph/evidence_writer"

class RetrievalSearchTest < Plastic::TestCase
  def test_searches_literal_terms_with_bounded_results_and_stable_ties
    writer.write("1", "z.md", "needle -- quoted \"term\"")
    writer.write("2", "a.md", "needle -- quoted \"term\"")

    rows = retrieval.search('needle -- quoted "term"')

    assert_equal [["2", "a.md", 1], ["1", "z.md", 1]], rows.map { |row| row.values_at("intent_id", "path", "position") }
    assert rows.all? { |row| row.fetch("body").length <= 1600 }
  end

  def test_bounds_and_validates_search_limits
    assert_raises(Plastic::Graph::RetrievalGraph::InvalidSearch) { retrieval.search("") }
    assert_raises(Plastic::Graph::RetrievalGraph::InvalidSearch) { retrieval.search("needle", limit: 0) }
    assert_raises(Plastic::Graph::RetrievalGraph::InvalidSearch) { retrieval.search("needle", limit: 101) }
  end

  private

  def writer = Plastic::Graph::EvidenceWriter.new(store_graphs.databases.fetch(:knowledge), origin)
end
