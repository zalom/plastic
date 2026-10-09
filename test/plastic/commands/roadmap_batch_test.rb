# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/roadmap_batch"

class RoadmapBatchTest < Plastic::TestCase
  def call(*args) = plastic("roadmap", "batch", *args, table: Plastic::CLI::TABLE)

  def test_writing_a_batch_says_what_it_wrote_and_offers_the_show
    result = call("r1", "1", "--title", "Wave one", "--goal", "Ship it")

    assert_call result, code: 0,
      out: "batch: r1 1 Wave one\nwrote:  1 routine run in local.db\n        1 roadmap and 1 batch in work_graph.db\n\n" \
           "next: plastic roadmap show r1 --project global\nbecause: batch 1 of r1 is written\n"
  end

  def test_a_second_call_on_the_same_batch_rewrites_it
    call("r1", "1", "--title", "First", "--goal", "G1", "--done", "a")
    call("r1", "1", "--title", "Second", "--goal", "G2", "--done", "b")

    rows = store_graphs.retrieval.batches("r1")

    assert_equal ["Second"], rows.map(&:title)
  end

  def test_a_new_batch_with_no_title_is_named_by_its_position
    call("r1", "2", "--goal", "Ship it")

    assert_equal ["Batch 2"], store_graphs.retrieval.batches("r1").map(&:title)
  end

  def test_a_field_left_out_keeps_the_batch_word_for_it
    call("r1", "1", "--title", "First", "--goal", "G1", "--done", "a", "--done", "b")
    call("r1", "1", "--title", "Renamed")

    batch = store_graphs.retrieval.batches("r1").first

    assert_equal ["Renamed", "G1", %w[a b]], [batch.title, batch.goal, batch.done_lines]
  end

  def test_a_batch_write_keeps_the_roadmap_title
    call("r1", "1", "--title", "First")
    store_graphs.databases.fetch(:work).transaction { |batch| batch.put(:roadmaps, { slug: "r1", title: "Make it useful", goal: "G" }) }
    call("r1", "2", "--title", "Second")

    assert_equal "Make it useful", store_graphs.retrieval.roadmap("r1").title
  end
end
