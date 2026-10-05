# frozen_string_literal: true

require_relative "../../../test_helper"

class RetrievalMaintenanceTest < Plastic::TestCase
  def setup
    super
    open_intent
  end

  def knowledge = store_graphs.databases[:knowledge]

  def maintenance = Plastic::Graph::Retrieval::Maintenance.new(store_graphs.databases, Plastic::Graph::Origin.new(@plastic_home))

  def backfilled = Plastic::Graph::Retrieval::ReferenceBackfill.complete?(knowledge.path, origin)

  def forget_the_backfill = knowledge.transaction { |batch| batch.add("DELETE FROM retrieval_backfills") }

  def test_ready_documents_backfills_before_the_read
    forget_the_backfill

    assert maintenance.ready_documents { backfilled }
  end

  def test_ready_documents_returns_the_read
    assert_equal :read, maintenance.ready_documents { :read }
  end

  def test_a_search_of_current_evidence_before_the_backfill_is_refused
    forget_the_backfill

    error = assert_raises(Plastic::Graph::RetrievalGraph::MaintenanceRequired) { maintenance.search_current("alpha", limit: 5) }

    assert_equal "retrieval migration is required before a selected source can be read", error.message
  end

  def test_a_search_of_current_evidence_after_the_backfill_finds_rows
    maintenance.backfill

    assert_equal ["1"], maintenance.search_current("alpha", limit: 5).map { |row| row.fetch("intent_id") }
  end

  def test_a_search_backfills_first
    forget_the_backfill
    maintenance.search("alpha", limit: 5)

    assert backfilled
  end

  def test_repair_rebuilds_a_lost_search_row_and_reports_the_repaired_state
    knowledge.transaction { |batch| batch.add("DELETE FROM document_fts") }

    assert_equal({ repairable: false, missing: [] }, maintenance.repair)
    refute_empty knowledge.rows("SELECT 1 FROM document_fts")
  end
end
