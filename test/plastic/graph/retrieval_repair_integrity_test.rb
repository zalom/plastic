# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/graph/evidence_writer"

class RetrievalRepairIntegrityTest < Plastic::TestCase
  def test_repair_rebuilds_wrong_values_and_orphans_without_losing_revisions
    writer.write("1", "repair.md", "repair evidence")
    revision = knowledge.row("SELECT sha256, body FROM document_revisions")
    corrupt_derived_rows

    repair

    assert_repaired(revision)
  end

  private

  def assert_repaired(revision)
    assert_equal revision, knowledge.row("SELECT sha256, body FROM document_revisions")
    assert_equal ["repair evidence"], retrieval.search("repair").map { |row| row.fetch("body") }
    assert_equal [[1, 1]], knowledge.rows("SELECT line_start, line_end FROM document_passages").map(&:values)
  end

  def writer = Plastic::Graph::EvidenceWriter.new(knowledge, origin)
  def knowledge = store_graphs.databases.fetch(:knowledge)
  def repair = retrieval.repair!

  def corrupt_derived_rows
    knowledge.transaction do |batch|
      batch.add("UPDATE document_passages SET body = 'wrong', line_start = 9, line_end = 9")
      batch.add("UPDATE document_heads SET sha256 = 'wrong'")
      batch.add("UPDATE document_fts SET body = 'wrong', sha256 = 'wrong'")
      batch.add("INSERT INTO document_fts (body, intent_id, path, sha256, position, origin_id) VALUES ('orphan', '9', 'orphan.md', 'orphan', 1, :origin)", origin:)
    end
  end
end
