# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/graph/retrieval/evidence/writer"

class RetrievalEvidenceRowsTest < Plastic::TestCase
  Recording = Struct.new(:steps) do
    def put(table, _row) = steps << table

    def add(sql, **) = steps << sql[/\A\w+(?: OR IGNORE)? \w+ \w+/]
  end

  def document = Plastic::Graph::Retrieval::Evidence::Document.new("1", "plan.md", "Body\n", now: STAMP)

  def test_the_rows_are_written_canonical_then_immutable_then_current
    batch = Recording.new([])
    Plastic::Graph::Retrieval::Evidence::Rows.new(batch, document, origin).write

    assert_equal [:documents, "INSERT OR IGNORE INTO document_revisions", :document_heads], batch.steps
  end

  def test_the_rows_write_no_passage_themselves
    batch = Recording.new([])
    Plastic::Graph::Retrieval::Evidence::Rows.new(batch, document, origin).write

    assert_empty batch.steps.grep(/document_passages/)
  end

  def test_the_rows_write_no_search_row_themselves
    batch = Recording.new([])
    Plastic::Graph::Retrieval::Evidence::Rows.new(batch, document, origin).write

    assert_empty batch.steps.grep(/document_fts/)
  end

  def test_one_search_row_for_each_passage_after_a_write
    store_database.transaction { |batch| Plastic::Graph::Retrieval::Evidence::Rows.new(batch, document, origin).write }
    reindex

    assert_equal store_database.rows("SELECT 1 FROM document_passages").size, store_database.rows("SELECT 1 FROM document_fts").size
  end

  def test_the_written_rows_read_back_from_every_evidence_table
    store_database.transaction { |batch| Plastic::Graph::Retrieval::Evidence::Rows.new(batch, document, origin).write }

    reindex

    assert_equal [1], row_counts(store_database, %w[documents document_revisions document_heads])
    assert_equal [1], row_counts(store_database, %w[document_passages document_fts])
  end

  def row_counts(database, tables) = tables.map { |table| database.rows("SELECT 1 FROM #{table}").size }.uniq
end
