# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/next_roadmap"

class WorkflowNextRoadmapTest < Plastic::TestCase
  include RoadmapHelper

  def setup
    super
    roadmap
    item("a")
  end

  def next_item(slug: "r1", position: nil) = run_workflow(Plastic::Workflows::NextRoadmap, slug:, position:)

  def test_the_first_ready_item_is_offered_and_blocked_items_are_named
    item("b", after: ["a"])

    outcome, context = next_item

    assert_equal [:ready, "a", ["b: blocked"]], [outcome, context.ready_id, context.printed]
  end

  def test_a_lone_ready_item_is_printed
    assert_equal ["a: ready"], next_item.last.printed
  end

  def test_a_roadmap_with_every_item_dropped_is_delivered
    store_graphs.work.drop_item("r1", "a")

    assert_equal :delivered, next_item.first
  end

  def test_items_in_flight_leave_the_roadmap_waiting
    store_graphs.work.start_roadmap_item("r1", "a")

    assert_equal [:waiting, ["a: in flight"]], next_item.then { |outcome, context| [outcome, context.printed] }
  end

  def test_a_position_limits_the_search_to_its_batch
    store_graphs.work.write_batch("r1", 2, fields: roadmap_fields("Later"))
    item("c", batch: 2)

    _outcome, context = next_item(position: "2")

    assert_equal ["c", ["c: ready"]], [context.ready_id, context.printed]
  end

  def test_an_unknown_roadmap_fails_the_call
    assert_equal "code_next_roadmap, gate: no roadmap r9", next_item(slug: "r9").first.message
  end
end
