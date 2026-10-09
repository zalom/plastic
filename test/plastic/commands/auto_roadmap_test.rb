# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/auto"

class AutoRoadmapTest < Plastic::TestCase
  include RoadmapHelper
  include AutoHelper

  def test_the_old_start_word_is_a_usage_error
    clear_intent

    result = call("start", "1")

    assert_equal [2, [], "open"], [result.code, lock_rows, retrieval.intent("1").status]
  end

  def test_auto_start_alone_reads_start_as_a_roadmap
    result = call("start")

    assert_equal [1, []], [result.code, lock_rows]
    assert_includes result.err, "no roadmap start"
  end

  def test_an_intent_shaped_slug_reads_as_an_intent
    store_graphs.work.write_batch("2026", 1, fields: roadmap_fields("T", goal: "G", done: "d"))

    result = call("2026")

    assert_equal 1, result.code
    assert_includes result.err, "no intent 2026 in this store"
  end

  def test_an_unknown_roadmap_fails
    result = call("r9")

    assert_equal [1, []], [result.code, lock_rows]
    assert_includes result.err, "no roadmap r9"
  end

  def test_a_roadmap_item_without_a_go_ahead_is_refused_with_no_lock
    roadmap
    item("a")
    intent_id, = store_graphs.work.start_roadmap_item("r1", "a")

    result = call("r1")

    assert_equal [3, []], [result.code, lock_rows]
    assert_includes result.err, "plastic intent approve #{intent_id}"
  end

  def test_a_roadmap_arms_its_in_flight_item
    roadmap
    item("a")
    intent_id, = store_graphs.work.start_roadmap_item("r1", "a")
    plastic("intent", "approve", intent_id, table: Plastic::CLI::TABLE)

    result = call("r1")

    assert_equal [0, "s-1", "active"], [result.code, retrieval.lock(intent_id)&.session_id, retrieval.intent(intent_id).status]
  end

  def test_a_roadmap_with_a_ready_item_offers_roadmap_start
    roadmap
    item("a")

    result = call("r1")

    assert_equal [0, [], "next: plastic roadmap start r1 a --project global"], [result.code, lock_rows, next_line(result)]
  end

  def test_a_resumed_roadmap_call_never_arms_a_stale_intent
    roadmap
    item("a")
    item("b")
    store_graphs.work.start_roadmap_item("r1", "a")
    failed = call("r1", env: { "PLASTIC_SESSION" => "" })
    store_graphs.work.drop_item("r1", "a")

    result = call("r1")

    assert_equal [1, 0, [], "next: plastic roadmap start r1 b --project global"], [failed.code, result.code, lock_rows, next_line(result)]
  end
end
