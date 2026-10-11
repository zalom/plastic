# frozen_string_literal: true

require_relative "../../../../../test_helper"
require_relative "../../../../../../scripts/lib/plastic/graph/retrieval/search/results"

class RetrievalSearchResultsStoreTest < Plastic::TestCase
  def store(slug) = Plastic::Graph::Retrieval::Search::Results::Store.new(@plastic_home, slug)

  def keep_a_file
    row = { name: "store/1--a/x.bin", mode: 0o100644, mtime: 0, sz: 1, data: Plastic::Graph::SQL::Bytes.new("\x00".b), intent_id: "1", sha256: "h" }
    store_graphs.databases[:references].transaction { |batch| batch.put(:sqlar, row) }
  end

  def test_a_store_with_every_graph_file_opens_its_retrieval_graph
    keep_a_file

    assert_equal "global", store("global").retrieval.store
  end

  def test_a_store_missing_a_graph_file_needs_maintenance
    error = assert_raises(Plastic::Graph::RetrievalGraph::MaintenanceRequired) { store("other").retrieval }

    assert_equal "retrieval maintenance is required before source other can be read", error.message
  end

  def test_a_store_with_no_backfill_marker_is_refused
    FileUtils.mkdir_p(File.join(@plastic_home, "stores", "old"))
    Plastic::Graph.open(home: @plastic_home, store: "old").databases.each_value { |database| database.rows("SELECT 1") }

    assert_equal "old", assert_raises(Plastic::Graph::RetrievalGraph::MaintenanceRequired) { store("old").retrieval }.slug
  end
end
