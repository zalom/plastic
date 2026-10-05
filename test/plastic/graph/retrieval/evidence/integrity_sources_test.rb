# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../scripts/lib/plastic/graph/retrieval/evidence/writer"

class RetrievalEvidenceIntegritySourcesTest < Plastic::TestCase
  Evidence = Plastic::Graph::Retrieval::Evidence
  SQL_TEXT = "SELECT path FROM documents"

  def setup
    super
    Evidence::Writer.new(knowledge, origin).write("1", "plan.md", "Body\n")
  end

  def knowledge = store_graphs.databases.fetch(:knowledge)

  def in_transaction(sql)
    found = nil
    knowledge.immediate_transaction { |_batch, connection| found = Evidence::IntegrityTransactionSource.new(connection).rows(sql) }
    found
  end

  def test_the_database_source_reads_rows
    assert_equal [{ "path" => "plan.md" }], Evidence::IntegrityDatabaseSource.new(knowledge).rows(SQL_TEXT)
  end

  def test_the_transaction_source_reads_rows_through_the_connection
    assert_equal ["plan.md"], in_transaction(SQL_TEXT).map { |row| row.fetch("path") }
  end

  def test_the_transaction_source_reads_an_empty_table_as_no_rows
    assert_empty in_transaction("SELECT path FROM documents WHERE 0")
  end
end
