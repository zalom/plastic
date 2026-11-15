# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/graph/retrieval/evidence/writer"

class RetrievalEvidenceIntegrityRebuilderTest < Plastic::TestCase
  def setup
    super
    Plastic::Graph::Retrieval::Evidence::Writer.new(knowledge, origin).write("1", "plan.md", "Rebuilt evidence\n")
    @expected = %w[document_heads document_passages document_fts].map { |table| rows(table) }
  end

  def knowledge = store_graphs.databases.fetch(:knowledge)

  def rows(table) = knowledge.rows("SELECT * FROM #{table} ORDER BY 1, 2, 3")

  def rebuild
    snapshot = Plastic::Graph::Retrieval::Evidence::IntegritySnapshot.new(knowledge, origin).capture
    knowledge.transaction { |batch| Plastic::Graph::Retrieval::Evidence::IntegrityRebuilder.new(origin).rebuild(batch, snapshot) }
  end

  def test_a_rebuild_writes_back_the_same_derived_rows
    knowledge.transaction { |batch| %w[document_heads document_passages document_fts].each { |table| batch.add("DELETE FROM #{table}") } }
    rebuild

    assert_equal @expected.map(&:size), %w[document_heads document_passages document_fts].map { |table| rows(table).size }
  end

  def test_a_rebuild_leaves_one_search_row_for_each_passage
    rebuild

    assert_equal rows("document_passages").size, rows("document_fts").size
  end

  def recorded_sql
    sqls = []
    recording = Object.new
    recording.define_singleton_method(:add) { |sql, **| sqls << sql }
    snapshot = Plastic::Graph::Retrieval::Evidence::IntegritySnapshot.new(knowledge, origin).capture
    Plastic::Graph::Retrieval::Evidence::IntegrityRebuilder.new(origin).rebuild(recording, snapshot)
    sqls
  end

  def test_a_rebuild_clears_the_search_rows_of_the_origin_before_the_heads
    clears = recorded_sql.grep(/\ADELETE FROM/)

    assert_operator clears.index { |sql| sql.include?("document_fts") }, :<, clears.index { |sql| sql.include?("document_heads") }
  end

  def test_a_rebuild_writes_no_search_row_itself
    assert_empty recorded_sql.grep(/INSERT INTO document_fts/)
  end

  def test_a_rebuild_drops_a_derived_row_with_no_source
    knowledge.transaction { |batch| batch.add("INSERT INTO document_heads (intent_id, path, sha256, updated_at, origin_id) VALUES ('9', 'x.md', 's', 't', :origin)", origin:) }
    rebuild

    assert_equal ["1"], rows("document_heads").map { |row| row.fetch("intent_id") }
  end

  def test_a_rebuild_leaves_the_rows_of_another_origin
    knowledge.transaction { |batch| batch.add("INSERT INTO document_heads (intent_id, path, sha256, updated_at, origin_id) VALUES ('9', 'x.md', 's', 't', 'beef')") }
    rebuild

    assert_equal %w[1 9], rows("document_heads").map { |row| row.fetch("intent_id") }
  end
end
