# frozen_string_literal: true

require_relative "../../../test_helper"

class RetrievalMaintenanceTest < Plastic::TestCase
  def setup
    super
    open_intent
    maintenance.repair
  end

  def maintenance = Plastic::Graph::Retrieval::Maintenance.new(store_graphs.databases, Plastic::Graph::Origin.new(@plastic_home))

  def test_a_search_finds_the_indexed_rows
    assert_equal ["1"], maintenance.search("alpha", limit: 5).map { |row| row.fetch("intent_id") }
  end

  def test_a_search_without_the_retrieval_file_says_to_run_doctor
    lose_retrieval_file

    error = assert_raises(Plastic::Graph::RetrievalGraph::MaintenanceRequired) { maintenance.search("alpha", limit: 5) }

    assert_match(/plastic doctor/, error.message)
  end

  def test_repair_rebuilds_a_lost_search_row_and_reports_the_repaired_state
    derived.transaction { |batch| batch.add("DELETE FROM document_fts") }

    assert_equal({ repairable: false, missing: [] }, maintenance.repair)
    refute_empty derived.rows("SELECT 1 FROM document_fts")
  end
end
