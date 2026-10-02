# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/roadmap_batch"
require_relative "../../../scripts/lib/plastic/commands/roadmap_add"

class RoadmapAddTest < Plastic::TestCase
  def call(*args) = plastic("roadmap", "add", *args, table: Plastic::CLI::TABLE)

  def batch(n = "1") = plastic("roadmap", "batch", "r1", n, "--title", "T", "--goal", "G", "--done", "d", table: Plastic::CLI::TABLE)

  def test_after_naming_an_item_off_the_roadmap_exits_1_with_nothing_written
    batch

    result = call("r1", "1", "a", "--title", "A", "--after", "ghost")

    assert_equal 1, result.code
    assert_empty store_graphs.retrieval.roadmap_items("r1")
  end

  def test_after_naming_an_item_off_the_roadmap_writes_no_edge
    batch
    call("r1", "1", "a", "--title", "A", "--after", "ghost")

    assert_empty store_graphs.retrieval.roadmap_edges("r1")
  end

  def test_a_loop_exits_3_and_one_edge_row_exists
    batch
    call("r1", "1", "a", "--title", "A")
    call("r1", "1", "b", "--title", "B", "--after", "a")

    result = call("r1", "1", "a", "--after", "b")

    assert_equal 3, result.code
    assert_equal 1, store_graphs.retrieval.roadmap_edges("r1").size
  end

  def test_an_item_refused_for_a_missing_batch_is_added_once_the_batch_exists
    call("r1", "1", "a", "--title", "A")
    batch

    result = call("r1", "1", "a", "--title", "A")

    assert_equal 0, result.code
    assert_equal ["a"], store_graphs.retrieval.roadmap_items("r1").map(&:item)
  end

  def test_an_existing_item_cannot_depend_on_itself
    batch
    call("r1", "1", "a", "--title", "A")

    result = call("r1", "1", "a", "--after", "a")

    assert_equal 3, result.code
    assert_empty store_graphs.retrieval.roadmap_edges("r1")
  end
end
