# frozen_string_literal: true

require_relative "../../../test_helper"

class RetrievalRoadmapReadsTest < Plastic::TestCase
  def put(table, row) = store_graphs.databases[:work].transaction { |batch| batch.put(table, row) }

  def setup
    super
    put(:roadmaps, { slug: "plan", title: "Plan" })
    put(:batches, { roadmap: "plan", position: 1, title: "B1" })
    put(:roadmap_items, { roadmap: "plan", item: "a", batch: 1, position: 1 })
    put(:roadmap_edges, { roadmap: "plan", from: "a", to: "b", kind: "needs" })
    put(:roadmap_log, { roadmap: "plan", position: 1, text: "Opened" })
  end

  def test_the_retrieval_graph_reads_the_roadmap_and_its_batches
    read = retrieval

    assert_equal ["Plan", ["B1"]], [read.roadmap("plan").title, read.batches("plan").map(&:title)]
  end

  def test_the_retrieval_graph_reads_the_items_edges_and_log
    read = retrieval

    assert_equal [["a"], ["b"], ["Opened"]], [read.roadmap_items("plan").map(&:item), read.roadmap_edges("plan").map(&:to), read.roadmap_log("plan").map(&:text)]
  end
end
