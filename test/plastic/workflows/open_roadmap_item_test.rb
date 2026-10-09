# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/open_roadmap_item"

class OpenRoadmapItemTest < Plastic::TestCase
  include RoadmapHelper

  def setup
    super
    roadmap
    item("a")
  end

  def start(item_id) = run_workflow(Plastic::Workflows::OpenRoadmapItem, slug: "r1", item_id:)

  def test_a_ready_item_opens_its_intent_and_prints_its_files
    outcome, context = start("a")

    assert_equal [:done, "intent: 1"], [outcome, context.printed.first]
    assert_equal "1", sole(retrieval.roadmap_items("r1")).intent_id
  end

  def test_a_blocked_item_is_refused_with_no_intent
    item("b", after: ["a"])

    outcome, = start("b")

    assert_equal [Plastic::Refused, "item b is blocked, not ready"], [outcome.class, outcome.message]
    assert_nil retrieval.intent("1")
  end

  def test_an_unknown_item_fails_the_call
    assert_equal "code_open_roadmap_item, gate: no item z on roadmap r1", start("z").first.message
  end
end
