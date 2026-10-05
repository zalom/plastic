# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../scripts/lib/plastic/graph/retrieval/evidence/writer"

class RetrievalEvidenceIntegrityTest < Plastic::TestCase
  Integrity = Plastic::Graph::Retrieval::Evidence::Integrity

  def setup
    super
    @calls = 0
    Plastic::Graph::Retrieval::Evidence::Writer.new(knowledge, origin).write("1", "plan.md", "Integrity evidence\n")
  end

  def knowledge = store_graphs.databases.fetch(:knowledge)

  def integrity = Integrity.new(knowledge, origin, before_rebuild: -> { @calls += 1 })

  def drop(table) = knowledge.transaction { |batch| batch.add("DELETE FROM #{table}") }

  def test_whole_evidence_reports_nothing_to_repair
    assert_equal({ repairable: false, missing: [] }, integrity.report)
  end

  def test_a_lost_search_row_reports_repairable
    drop("document_fts")

    assert integrity.report.fetch(:repairable)
  end

  def test_repair_rebuilds_the_lost_rows_after_its_hook
    drop("document_fts")
    integrity.repair

    assert_equal [false, 1], [integrity.report.fetch(:repairable), @calls]
  end

  def test_a_document_with_no_revision_cannot_be_repaired
    drop("document_revisions")

    error = assert_raises(Integrity::EvidenceLost) { integrity.repair }
    assert_equal "1:plan.md has no immutable revision", error.message
  end
end
