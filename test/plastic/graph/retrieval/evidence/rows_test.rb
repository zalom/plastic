# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/graph/retrieval/evidence/writer"

class RetrievalEvidenceRowsTest < Plastic::TestCase
  Recording = Struct.new(:steps) do
    def put(table, _row) = steps << table

    def add(sql, **) = steps << sql[/\A\w+(?: OR IGNORE)? \w+ \w+/]
  end

  def document = Plastic::Graph::Retrieval::Evidence::Document.new("1", "plan.md", "Body\n", now: STAMP)

  def knowledge = store_graphs.databases.fetch(:knowledge)

  def test_the_rows_are_written_canonical_then_immutable_then_current
    batch = Recording.new([])
    Plastic::Graph::Retrieval::Evidence::Rows.new(batch, document, origin).write { batch.steps << :between }

    assert_equal [:documents, "INSERT OR IGNORE INTO document_revisions", "INSERT OR IGNORE INTO document_passages", :between, :document_heads], batch.steps
  end

  def test_the_passages_are_written_before_the_head
    batch = Recording.new([])
    Plastic::Graph::Retrieval::Evidence::Rows.new(batch, document, origin).write { nil }

    assert_operator batch.steps.index("INSERT OR IGNORE INTO document_passages"), :<, batch.steps.index(:document_heads)
  end

  def test_the_rows_write_no_search_row_themselves
    batch = Recording.new([])
    Plastic::Graph::Retrieval::Evidence::Rows.new(batch, document, origin).write { nil }

    assert_empty batch.steps.grep(/document_fts/)
  end

  def test_one_search_row_for_each_passage_after_a_write
    knowledge.transaction { |batch| Plastic::Graph::Retrieval::Evidence::Rows.new(batch, document, origin).write { nil } }

    assert_equal knowledge.rows("SELECT 1 FROM document_passages").size, knowledge.rows("SELECT 1 FROM document_fts").size
  end

  def test_the_written_rows_read_back_from_every_evidence_table
    knowledge.transaction { |batch| Plastic::Graph::Retrieval::Evidence::Rows.new(batch, document, origin).write { nil } }

    assert_equal [1], %w[documents document_revisions document_passages document_heads document_fts].map { |table| knowledge.rows("SELECT 1 FROM #{table}").size }.uniq
  end
end
