# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/evidence/writer"

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

  def writer = Plastic::Graph::Retrieval::Evidence::Writer.new(store_graphs.databases.fetch(:store), origin, clock: FixedClock::CLOCK)
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

  def writer = Plastic::Graph::Retrieval::Evidence::Writer.new(database, origin, clock: FixedClock::CLOCK)

  def database = store_graphs.databases.fetch(:store)

  def query = '"common" AND "term"'

  def legacy_sql
    "SELECT intent_id, path, body, sha256, position, bm25(document_fts) AS score " \
      "FROM document_fts WHERE document_fts MATCH :query AND origin_id = :origin " \
      "ORDER BY score, intent_id, path, position LIMIT :limit"
  end
end

class RetrievalSearchPlainWordsTest < Plastic::TestCase
  def test_a_question_in_plain_words_finds_a_passage_that_holds_only_some_of_the_words
    writer.write("1", "a.md", "the retrieval graph gives context to work")
    reindex

    assert_equal [["1", "a.md"]], retrieval.search("what does the retrieval graph give to my deployment").map { |row| row.values_at("intent_id", "path") }
  end

  def test_the_passage_that_holds_more_of_the_words_ranks_first
    writer.write("1", "few.md", "context about deployment")
    writer.write("2", "most.md", "retrieval graph context for deployment of the store")
    reindex

    assert_equal %w[most.md few.md], retrieval.search("retrieval graph context deployment").map { |row| row.fetch("path") }
  end

  def test_a_quoted_phrase_ranks_the_passage_that_holds_the_phrase_first
    writer.write("1", "apart.md", "graph one, and later a retrieval note")
    writer.write("2", "phrase.md", "the retrieval graph is derived")
    reindex

    assert_equal "phrase.md", retrieval.search('"retrieval graph"').first.fetch("path")
  end

  def test_the_words_of_a_quoted_phrase_do_not_match_apart_as_the_phrase
    writer.write("1", "apart.md", "graph one, and later a retrieval note")
    reindex

    assert_empty retrieval.search('"retrieval graph"')
  end

  def test_a_stop_word_alone_does_not_match_every_passage
    writer.write("1", "a.md", "the store holds documents")
    writer.write("2", "b.md", "the index holds passages")
    reindex

    assert_equal ["b.md"], retrieval.search("what is the index").map { |row| row.fetch("path") }
  end

  def test_a_search_of_stop_words_only_still_searches_them
    writer.write("1", "a.md", "the end")
    reindex

    assert_equal ["a.md"], retrieval.search("the").map { |row| row.fetch("path") }
  end

  def test_the_fts_query_joins_terms_with_or_and_keeps_a_phrase_whole
    assert_equal '"retrieval graph" OR "context"', Plastic::Graph::Retrieval::Search.fts_query('"retrieval graph" what is the context')
  end

  private

  def writer = Plastic::Graph::Retrieval::Evidence::Writer.new(store_graphs.databases.fetch(:store), origin, clock: FixedClock::CLOCK)
end
