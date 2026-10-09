# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/show_roadmap"

class WorkflowShowRoadmapTest < Plastic::TestCase
  include RoadmapHelper

  def show(slug: "r1", position: nil) = run_workflow(Plastic::Workflows::ShowRoadmap, slug:, position:)

  def test_each_batch_is_printed_with_its_criteria_and_items
    roadmap(done: "it ships")
    item("a")
    item("b", after: ["a"])

    outcome, context = show

    assert_equal :done, outcome
    assert_equal ["batch 1: T - G", "  done: it ships", "item a: A - ready, needs nothing", "item b: B - blocked, needs a"],
      context.printed
  end

  def test_a_position_shows_only_its_batch
    roadmap
    store_graphs.work.write_batch("r1", 2, fields: roadmap_fields("Later"))

    assert_equal ["batch 2: Later"], show(position: "2").last.printed
  end

  def test_an_unknown_roadmap_fails_the_call
    assert_equal "code_show_roadmap, gate: no roadmap r9", show(slug: "r9").first.message
  end
end
