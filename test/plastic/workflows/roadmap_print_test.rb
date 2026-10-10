# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/roadmap_print"

class RoadmapPrintTest < Plastic::TestCase
  include RoadmapHelper

  def printed(position: nil)
    context = call_context(slug: "r1", position:)
    Plastic::Workflows::RoadmapPrint.call(context)
    context.printed
  end

  def test_each_batch_is_followed_by_its_own_items
    roadmap(done: "it ships")
    store_graphs.work.write_batch("r1", 2, fields: roadmap_fields("Later"))
    item("a")
    item("b", needs: ["a"], batch: 2)

    assert_equal ["batch 1: T - G", "  done: it ships", "item a: A - ready, needs nothing",
      "batch 2: Later", "item b: B - blocked, needs a"], printed
  end

  def test_a_position_prints_only_its_batch
    roadmap
    store_graphs.work.write_batch("r1", 2, fields: roadmap_fields("Later"))

    assert_equal ["batch 2: Later"], printed(position: "2")
  end
end
