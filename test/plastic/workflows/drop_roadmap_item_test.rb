# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/drop_roadmap_item"

class DropRoadmapItemTest < Plastic::TestCase
  Fields = Plastic::Graph::Knowledge::Roadmap::Writer::Fields

  def setup
    super
    work = store_graphs.work
    work.write_batch("r1", 1, fields: Fields.new(title: "T", goal: "G", done: "d"))
    work.add_item("r1", "a", 1, fields: Fields.new(title: "A", goal: nil, done: nil), after: [])
  end

  def drop(item_id, slug: "r1") = run_workflow(Plastic::Workflows::DropRoadmapItem, slug:, item_id:)

  def test_an_item_is_dropped_and_named
    outcome, context = drop("a")

    assert_equal [:done, ["dropped: a"]], [outcome, context.printed]
    assert_equal "dropped", sole(retrieval.roadmap_items("r1")).mark
  end

  def test_an_unknown_item_fails_the_call
    assert_equal "code_drop_roadmap_item, gate: no item z on roadmap r1", drop("z").first.message
  end

  def test_an_unknown_roadmap_fails_the_call
    assert_equal "code_drop_roadmap_item, gate: no roadmap r9", drop("a", slug: "r9").first.message
  end
end
