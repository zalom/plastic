# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/roadmap/batch"
require_relative "../../../../lib/plastic/commands/roadmap/add"

class RoadmapAddCaseTest < Plastic::TestCase
  def test_adding_the_first_item_prints_it_and_offers_the_roadmap
    shop_batch

    assert_case line('roadmap add shop 1 guest --title "Lock down guest orders"'), code: 0,
      out: ["item: guest Lock down guest orders", "next: plastic roadmap show shop"]
  end

  def test_adding_an_item_that_needs_another_prints_it_and_offers_the_roadmap
    shop_guest

    assert_case line('roadmap add shop 1 pay --title "Charge on confirm" --needs guest'), code: 0,
      out: ["item: pay Charge on confirm", "next: plastic roadmap show shop"]
  end

  def test_adding_to_a_batch_that_does_not_exist_exits_1_and_names_it
    assert_case line("roadmap add shop 1 guest"), code: 1, out: "", err: ["no batch 1 on roadmap shop"]
  end

  def test_an_item_that_needs_a_missing_item_exits_1_and_names_it
    shop_guest

    assert_case line("roadmap add shop 1 pay --needs nope"), code: 1, out: "", err: ["no item nope on roadmap shop"]
  end
end

class RoadmapAddTest < Plastic::TestCase
  def call(*args) = plastic("roadmap", "add", *args, table: Plastic::CLI::TABLE)

  def batch(n = "1")
    plastic("roadmap", "new", "r1", table: Plastic::CLI::TABLE) unless store_graphs.retrieval.roadmap("r1")
    plastic("roadmap", "batch", "r1", n, "--title", "T", "--goal", "G", "--done", "d", table: Plastic::CLI::TABLE)
  end

  def test_after_is_gone
    batch

    assert_equal 2, call("r1", "1", "a", "--title", "A", "--after", "ghost").code
  end

  def test_needs_naming_an_item_off_the_roadmap_exits_1_with_nothing_written
    batch

    result = call("r1", "1", "a", "--title", "A", "--needs", "ghost")

    assert_equal 1, result.code
    assert_empty store_graphs.retrieval.roadmap_items("r1")
  end

  def test_needs_naming_an_item_off_the_roadmap_writes_no_edge
    batch
    call("r1", "1", "a", "--title", "A", "--needs", "ghost")

    assert_empty store_graphs.retrieval.roadmap_edges("r1")
  end

  def test_a_loop_exits_3_and_one_edge_row_exists
    batch
    call("r1", "1", "a", "--title", "A")
    call("r1", "1", "b", "--title", "B", "--needs", "a")

    result = call("r1", "1", "a", "--needs", "b")

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

    result = call("r1", "1", "a", "--needs", "a")

    assert_equal 3, result.code
    assert_empty store_graphs.retrieval.roadmap_edges("r1")
  end
end
