# frozen_string_literal: true

require_relative "../../../test_helper"

class RetrievalRoadmapReaderTest < Plastic::TestCase
  def put(table, row) = store_graphs.databases[:work].transaction { |batch| batch.put(table, row) }

  def reader = Plastic::Graph::Retrieval::RoadmapReader.new(store_graphs.databases[:work], origin)

  def test_a_roadmap_reads_by_slug
    put(:roadmaps, { slug: "plan", title: "Plan" })

    assert_equal "Plan", reader.roadmap("plan").title
  end

  def test_a_missing_roadmap_reads_nil
    assert_nil reader.roadmap("plan")
  end

  def test_batches_read_in_position_order
    [2, 1].each { |position| put(:batches, { roadmap: "plan", position:, title: "B#{position}" }) }

    assert_equal %w[B1 B2], reader.batches("plan").map(&:title)
  end

  def test_items_read_by_batch_then_position
    put(:roadmap_items, { roadmap: "plan", item: "c", batch: 2, position: 1 })
    put(:roadmap_items, { roadmap: "plan", item: "b", batch: 1, position: 2 })
    put(:roadmap_items, { roadmap: "plan", item: "a", batch: 1, position: 1 })

    assert_equal %w[a b c], reader.items("plan").map(&:item)
  end

  def test_edges_read_in_numeric_order_of_their_start
    %w[10 9].each { |from| put(:roadmap_edges, { roadmap: "plan", from:, to: "1", kind: "needs" }) }

    assert_equal %w[9 10], reader.edges("plan").map(&:from)
  end

  def test_log_lines_read_in_position_order
    [2, 1].each { |position| put(:roadmap_log, { roadmap: "plan", position:, text: "L#{position}" }) }

    assert_equal %w[L1 L2], reader.log("plan").map(&:text)
  end

  def test_rows_of_another_roadmap_stay_out
    put(:batches, { roadmap: "other", position: 1, title: "B" })

    assert_empty reader.batches("plan")
  end
end
