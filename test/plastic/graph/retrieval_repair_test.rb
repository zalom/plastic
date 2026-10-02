# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/graph/evidence_writer"

class RetrievalRepairTest < Plastic::TestCase
  DERIVED_TABLES = %w[document_heads document_passages document_fts].freeze

  def test_repairs_each_corrupted_derived_table_from_current_documents
    DERIVED_TABLES.each do |table|
      index_current_document
      knowledge.transaction { |batch| batch.add("DELETE FROM #{table}") }

      retrieval.repair!

      assert_repaired
    end
  end

  def test_repair_rebuilds_wrong_values_and_orphans_without_deleting_immutable_revisions
    index_current_document
    revision = knowledge.row("SELECT sha256, body FROM document_revisions")
    knowledge.transaction do |batch|
      batch.add("UPDATE document_passages SET body = 'wrong', line_start = 9, line_end = 9")
      batch.add("UPDATE document_heads SET sha256 = 'wrong'")
      batch.add("UPDATE document_fts SET body = 'wrong', sha256 = 'wrong'")
      batch.add("INSERT INTO document_fts (body, intent_id, path, sha256, position, origin_id) VALUES ('orphan', '9', 'orphan.md', 'orphan', 1, :origin)", origin:)
    end

    retrieval.repair!

    assert_equal revision, knowledge.row("SELECT sha256, body FROM document_revisions")
    assert_equal [[revision.fetch("sha256"), 1, "repair evidence", 1, 1]],
      knowledge.rows("SELECT sha256, position, body, line_start, line_end FROM document_passages")
        .map { |row| row.values_at("sha256", "position", "body", "line_start", "line_end") }
    assert_equal [["1", "repair.md", "repair evidence", revision.fetch("sha256"), 1]],
      retrieval.search("repair").map { |row| row.values_at("intent_id", "path", "body", "sha256", "position") }
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
