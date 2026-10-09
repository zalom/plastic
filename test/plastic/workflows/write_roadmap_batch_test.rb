# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/write_roadmap_batch"

class WriteRoadmapBatchTest < Plastic::TestCase
  def write_batch(title)
    store_graphs.work.create_roadmap("r1", title: nil, goal: nil) unless retrieval.roadmap("r1")
    run_workflow(Plastic::Workflows::WriteRoadmapBatch, slug: "r1", position: "1", title:, goal: "Ship", done: "it ships")
  end

  def test_a_batch_is_written_and_printed
    outcome, context = write_batch("First")

    assert_equal [:done, ["batch: r1 1 First"]], [outcome, context.printed]
    assert_equal %w[First Ship], sole(retrieval.batches("r1")).to_h.values_at(:title, :goal)
  end

  def test_writing_the_same_position_again_replaces_the_batch
    write_batch("First")

    write_batch("Second")

    assert_equal "Second", sole(retrieval.batches("r1")).title
  end
end
