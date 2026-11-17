# frozen_string_literal: true

require_relative "../../../test_helper"

class RetrievalStoreReadsTest < Plastic::TestCase
  def put(table, row) = store_graphs.databases.fetch(:store).transaction { |batch| batch.put(table, row) }

  def test_the_retrieval_graph_reads_the_printed_files
    put(:printed, { path: "store/index.json", sha256: "a", at: "t" })

    assert_equal({ "store/index.json" => "a" }, retrieval.printed)
  end
end
