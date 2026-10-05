# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/roadmap_lines"

class RoadmapLinesTest < Minitest::Test
  Batch = Struct.new(:position, :title, :goal, :done_lines)
  Item = Struct.new(:item, :title)
  Edge = Struct.new(:from, :to)

  def lines = Plastic::Workflows::RoadmapLines

  def test_a_batch_is_its_heading_then_one_line_for_each_done_criterion
    batch = Batch.new(position: 1, title: "T", goal: "G", done_lines: ["it ships"])

    assert_equal ["batch 1: T - G", "  done: it ships"], lines.batch(batch)
  end

  def test_a_batch_with_no_goal_has_a_heading_with_no_dash
    assert_equal ["batch 2: Later"], lines.batch(Batch.new(position: 2, title: "Later", goal: "", done_lines: []))
  end

  def test_an_item_names_its_state_and_the_items_it_waits_for
    edges = [Edge.new(from: "a", to: "b"), Edge.new(from: "c", to: "d")]

    assert_equal "item b: B - blocked, waits for a", lines.item(Item.new(item: "b", title: "B"), "blocked", edges)
  end

  def test_an_item_with_no_edge_waits_for_nothing
    assert_equal "item a: A - ready, waits for nothing", lines.item(Item.new(item: "a", title: "A"), "ready", [])
  end
end
