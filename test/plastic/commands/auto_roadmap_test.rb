# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/commands/auto"

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
    intent_id, = store_graphs.work.open_roadmap_item("r1", "a")

    result = call("r1")

    assert_equal [3, []], [result.code, lock_rows]
    assert_includes result.err, "plastic intent approve #{intent_id}"
  end

  def test_a_roadmap_arms_its_in_flight_item
    roadmap
    item("a")
    intent_id, = store_graphs.work.open_roadmap_item("r1", "a")
    plastic("intent", "approve", intent_id, table: Plastic::CLI::TABLE)

    result = call("r1")

    assert_equal [0, "s-1", "in_progress"], [result.code, retrieval.lock(intent_id)&.session_id, retrieval.intent(intent_id).status]
  end

  def test_a_roadmap_with_a_ready_item_offers_roadmap_open
    roadmap
    item("a")

    result = call("r1")

    assert_equal [0, [], "next: plastic roadmap open r1 a"], [result.code, lock_rows, next_line(result)]
  end

  def test_a_resumed_roadmap_call_never_arms_a_stale_intent
    roadmap
    item("a")
    item("b")
    store_graphs.work.open_roadmap_item("r1", "a")
    failed = call("r1", env: { "PLASTIC_SESSION" => "" })
    store_graphs.work.drop_item("r1", "a")

    result = call("r1")

    assert_equal [1, 0, [], "next: plastic roadmap open r1 b"], [failed.code, result.code, lock_rows, next_line(result)]
  end
def armed_item
  roadmap
  item("a")
  intent_id, = store_graphs.work.open_roadmap_item("r1", "a")
  plastic("intent", "approve", intent_id, table: Plastic::CLI::TABLE)
  intent_id
end

def test_a_roadmap_whose_picked_intent_has_a_savepoint_changed_by_hand_is_refused_and_kept
  intent_id = armed_item
  path = "#{retrieval.intent(intent_id).dir}/savepoint.md"
  write(path, "by hand\n")

  result = call("r1")

  assert_equal [1, [], "by hand\n", true, "next: plastic sync up"], [result.code, lock_rows, File.read(store_path(path)), result.err.include?("#{path} changed by hand"), next_line(result)], result.err
end

def test_a_roadmap_with_a_ready_item_is_not_refused_for_a_file_of_another_intent
  roadmap
  item("a")
  other = open_intent("Other")
  write("#{other.dir}/savepoint.md", "by hand\n")

  result = call("r1")

  assert_equal [0, "next: plastic roadmap open r1 a"], [result.code, next_line(result)], result.err
end

def test_a_delivered_roadmap_offers_roadmap_show_and_is_not_refused
  roadmap
  item("a")
  store_graphs.work.drop_item("r1", "a")

  result = call("r1")

  assert_equal [0, "next: plastic roadmap show r1"], [result.code, next_line(result)], result.err
end
end
