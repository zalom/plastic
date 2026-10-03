# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/graph/evidence_writer"

class RetrievalRepairTest < Plastic::TestCase
  DERIVED_TABLES = %w[document_heads document_passages document_fts].freeze

  def test_repairs_each_corrupted_derived_table_from_current_documents
    DERIVED_TABLES.each do |table|
      index_current_document
      knowledge.transaction { |batch| batch.add("DELETE FROM #{table}") }

      retrieval.repair

      assert_repaired
    end
  end

  private

  def index_current_document
    Plastic::Graph::EvidenceWriter.new(knowledge, origin).write("1", "repair.md", "repair evidence")
  end

  def knowledge = store_graphs.databases.fetch(:knowledge)

  def assert_repaired
    assert_equal ["repair evidence"], retrieval.search("repair").map { |row| row.fetch("body") }
    assert_equal [1], DERIVED_TABLES.map { |table| knowledge.row("SELECT count(*) AS n FROM #{table}").fetch("n") }.uniq
  end
end
