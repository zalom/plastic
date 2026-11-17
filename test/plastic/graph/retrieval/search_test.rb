# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/retrieval/evidence/writer"

class RetrievalSearchTest < Plastic::TestCase
  def test_searches_literal_terms_with_bounded_results_and_stable_ties
    writer.write("1", "z.md", "needle -- quoted \"term\"")
    writer.write("2", "a.md", "needle -- quoted \"term\"")
    reindex

    rows = retrieval.search('needle -- quoted "term"')

    assert_equal [["1", "z.md", 1], ["2", "a.md", 1]], rows.map { |row| row.values_at("intent_id", "path", "position") }
    assert rows.all? { |row| row.fetch("body").length <= 1600 }
  end

  def test_bounds_and_validates_search_limits
    assert_raises(Plastic::Graph::RetrievalGraph::InvalidSearch) { retrieval.search("") }
    assert_raises(Plastic::Graph::RetrievalGraph::InvalidSearch) { retrieval.search("needle", limit: 0) }
    assert_raises(Plastic::Graph::RetrievalGraph::InvalidSearch) { retrieval.search("needle", limit: 101) }
  end

  private

  def writer = Plastic::Graph::Retrieval::Evidence::Writer.new(store_graphs.databases.fetch(:store), origin)
end

class RetrievalSearchOrderTest < Plastic::TestCase
  def test_search_keeps_bm25_order_and_stable_cutoff_ties
    index("1", "z.md")
    index("2", "a.md")
    index("2", "b.md")
    reindex

    assert_equal legacy_rows, retrieval.search("common term", limit: 2)
    assert query_plan.any? { |row| row.fetch("detail").include?("USE TEMP B-TREE") }
  end

  private

  def index(intent_id, path)
    writer.write(intent_id, path, "common term")
  end

  def legacy_rows
    store_database.rows(legacy_sql, query:, origin:, limit: 2)
  end

  def query_plan
    store_database.rows("EXPLAIN QUERY PLAN #{Plastic::Graph::RetrievalGraph::SEARCH_SQL}", query:, origin:, limit: 2)
  end

  def writer = Plastic::Graph::Retrieval::Evidence::Writer.new(database, origin)

  def database = store_graphs.databases.fetch(:store)

  def query = '"common" AND "term"'

  def legacy_sql
    "SELECT intent_id, path, body, sha256, position, bm25(document_fts) AS score " \
      "FROM document_fts WHERE document_fts MATCH :query AND origin_id = :origin " \
      "ORDER BY score, intent_id, path, position LIMIT :limit"
  end
end
