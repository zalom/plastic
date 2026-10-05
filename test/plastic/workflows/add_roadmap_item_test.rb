# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/add_roadmap_item"

class AddRoadmapItemTest < Plastic::TestCase
  Fields = Plastic::Graph::Knowledge::Roadmap::Writer::Fields

  def batch = store_graphs.work.write_batch("r1", 1, fields: Fields.new(title: "T", goal: "G", done: "d"))

  def add(item_id, after: []) = run_workflow(Plastic::Workflows::AddRoadmapItem, slug: "r1", item_id:, position: "1",
    title: item_id.upcase, goal: nil, done: nil, after:)

  def test_an_item_is_added_to_its_batch_and_named
    batch

    outcome, context = add("a")

    assert_equal [:done, ["item: a A"]], [outcome, context.printed]
    assert_equal ["a"], retrieval.roadmap_items("r1").map(&:item)
  end

  def test_a_missing_batch_fails_with_no_item
    outcome, = add("a")

    assert_equal "code_add_roadmap_item, gate: no batch 1 on roadmap r1", outcome.message
    assert_empty retrieval.roadmap_items("r1")
  end

  def test_a_loop_is_refused_with_one_edge_left
    batch
    add("a")
    add("b", after: ["a"])

    outcome, = add("a", after: ["b"])

    assert_kind_of Plastic::Refused, outcome
    assert_equal 1, retrieval.roadmap_edges("r1").size
  end
end
