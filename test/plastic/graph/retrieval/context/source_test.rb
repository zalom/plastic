# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../scripts/lib/plastic/graph/retrieval/context/source"

class RetrievalContextSourceTest < Plastic::TestCase
  REFERENCE = "plastic://global/1/plan.md"

  def source = Plastic::Graph::Retrieval::Context::Source.new(@plastic_home)

  def keep_a_file
    row = { name: "store/1--a/x.bin", mode: 0o100644, mtime: 0, sz: 1, data: Plastic::Graph::SQL::Bytes.new("\x00".b), intent_id: "1", sha256: "h" }
    store_graphs.databases[:references].transaction { |batch| batch.put(:sqlar, row) }
  end

  def test_a_ready_store_opens_its_retrieval_graph
    keep_a_file
    retrieval.backfill

    assert_equal "global", source.retrieval(REFERENCE).store
  end

  def test_a_store_missing_a_graph_file_needs_maintenance
    error = assert_raises(Plastic::Graph::RetrievalGraph::MaintenanceRequired) { source.retrieval("plastic://other/1/plan.md") }

    assert_equal "retrieval maintenance is required before source other can be read", error.message
  end

  def test_a_store_not_yet_backfilled_needs_maintenance
    keep_a_file

    assert_raises(Plastic::Graph::RetrievalGraph::MaintenanceRequired) { source.retrieval(REFERENCE) }
  end
end
