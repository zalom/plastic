# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/workflows/code/roadmap/open"

class OpenRoadmapItemTest < Plastic::TestCase
  include RoadmapHelper

  def setup
    super
    roadmap
    item("a")
  end

  def start(item_id) = run_workflow(Plastic::Workflows::Code::Roadmap::Open, slug: "r1", item_id:)

  def test_a_ready_item_opens_its_intent_and_prints_its_files
    outcome, context = start("a")

    assert_equal [:done, "intent: 1"], [outcome, context.printed.first]
    assert_equal "1", sole(retrieval.roadmaps.items("r1")).intent_id
  end

  def test_a_blocked_item_is_refused_with_no_intent
    item("b", needs: ["a"])

    error = assert_raises(Plastic::Refused) { start("b") }

    assert_equal [Plastic::Refused, "item b is blocked, not ready"], [error.class, error.message]
    assert_nil retrieval.intent("1")
  end

  def test_an_unknown_item_fails_the_call
    assert_equal "no item z on roadmap r1", assert_raises(Plastic::Failed) { start("z") }.message
  end
end
