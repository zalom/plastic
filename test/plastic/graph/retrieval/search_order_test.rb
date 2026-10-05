# frozen_string_literal: true

require_relative "../../../test_helper"

class RetrievalSearchOrderTest < Plastic::TestCase
  def test_search_keeps_bm25_order_and_stable_cutoff_ties
    index("1", "z.md")
    index("2", "a.md")
    index("2", "b.md")

    assert_equal legacy_rows, retrieval.search("common term", limit: 2)
    assert query_plan.any? { |row| row.fetch("detail").include?("USE TEMP B-TREE") }
  end

  private

  def index(intent_id, path)
    writer.write(intent_id, path, "common term")
  end

  def legacy_rows
    database.rows(legacy_sql, query:, origin:, limit: 2)
  end

  def query_plan
    database.rows("EXPLAIN QUERY PLAN #{Plastic::Graph::RetrievalGraph::SEARCH_SQL}", query:, origin:, limit: 2)
  end

  def writer = Plastic::Graph::Retrieval::Evidence::Writer.new(database, origin)

  def database = store_graphs.databases.fetch(:knowledge)

  def query = '"common" AND "term"'

  def legacy_sql
    "SELECT intent_id, path, body, sha256, position, bm25(document_fts) AS score " \
      "FROM document_fts WHERE document_fts MATCH :query AND origin_id = :origin " \
      "ORDER BY score, intent_id, path, position LIMIT :limit"
  end
end
