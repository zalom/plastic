# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/roadmap/auto"

class RoadmapAutoTest < Plastic::TestCase
  include RoadmapHelper
  include AutoHelper

  def opened(item_id) = store_graphs.work.open_roadmap_item("r1", item_id).first

  def approved_item
    roadmap
    item("a")
    opened("a").tap { |intent_id| approve(intent_id) }
  end

  def intent_count = retrieval.intents.size

  def test_an_in_flight_item_goes_in_progress
    intent_id = approved_item

    result = roadmap_auto("r1")

    assert_equal [0, "in_progress", [], "next: plastic intent brief #{intent_id}"],
      [result.code, status_of(intent_id), claim_rows, next_line(result)]
  end

  def test_a_ready_item_opens_its_intent_and_starts_it
    roadmap
    item("a")

    result = roadmap_auto("r1")

    intent_id = roadmaps.items("r1").first.intent_id
    assert_equal [0, "in_progress"], [result.code, status_of(intent_id)]
    assert_includes result.out, "intent: #{intent_id}"
  end

  def test_a_started_ready_item_without_a_go_ahead_offers_the_spec
    roadmap
    item("a")

    result = roadmap_auto("r1")

    assert_equal "next: plastic intent spec #{roadmaps.items("r1").first.intent_id}", next_line(result)
  end

  def test_a_second_call_starts_the_same_item_and_opens_no_second_intent
    roadmap
    item("a")
    roadmap_auto("r1")

    result = roadmap_auto("r1")

    assert_equal [0, 1, "in_progress"], [result.code, intent_count, status_of(roadmaps.items("r1").first.intent_id)]
  end

  def test_an_item_held_by_another_session_is_skipped_and_the_roadmap_waits
    intent_id = approved_item
    store_graphs.work.add_node(intent_id:, title: "Build")
    store_graphs.work.claim_node(intent_id:, id: "n1", by: "s-2")

    result = roadmap_auto("r1")

    assert_equal [0, "open", "next: plastic roadmap auto r1"], [result.code, status_of(intent_id), next_line(result)]
  end

  def test_a_parked_item_is_skipped_and_the_roadmap_waits
    intent_id = approved_item
    set_status(intent_id, "parked")

    result = roadmap_auto("r1")

    assert_equal [0, "parked", "next: plastic roadmap auto r1"], [result.code, status_of(intent_id), next_line(result)]
  end

  def test_a_delivered_roadmap_offers_roadmap_show
    roadmap
    item("a")
    store_graphs.work.drop_item("r1", "a")

    result = roadmap_auto("r1")

    assert_equal [0, "next: plastic roadmap show r1"], [result.code, next_line(result)], result.err
  end

  def test_an_unknown_roadmap_fails
    result = roadmap_auto("r9")

    assert_equal [1, []], [result.code, claim_rows]
    assert_includes result.err, "no roadmap r9"
  end

  def test_a_call_with_no_session_fails_and_names_intent_auto
    approved_item

    result = roadmap_auto("r1", env: { "PLASTIC_SESSION" => "" })

    assert_equal 1, result.code
    assert_includes result.err, "intent auto names no session; set PLASTIC_SESSION"
  end

  def test_a_resumed_call_never_starts_a_stale_intent
    roadmap
    item("a")
    item("b")
    opened("a")
    failed = roadmap_auto("r1", env: { "PLASTIC_SESSION" => "" })
    store_graphs.work.drop_item("r1", "a")

    result = roadmap_auto("r1")

    started = roadmaps.items("r1").find { |row| row.item == "b" }.intent_id
    assert_equal [1, 0, "in_progress"], [failed.code, result.code, status_of(started)]
  end

  def test_a_picked_intent_whose_work_log_changed_by_hand_is_refused_and_kept
    intent_id = approved_item
    path = "#{retrieval.intent(intent_id).dir}/work.log"
    write(path, "by hand\n")

    result = roadmap_auto("r1")

    assert_equal [1, [], "by hand\n", true, "next: plastic sync up"], [result.code, claim_rows, File.read(store_path(path)), result.err.include?("#{path} changed since its last print on this home"), next_line(result)], result.err
  end

  def test_a_ready_item_is_not_refused_for_a_file_of_another_intent
    roadmap
    item("a")
    other = open_intent("Other")
    write("#{other.dir}/work.log", "by hand\n")

    result = roadmap_auto("r1")

    assert_equal 0, result.code, result.err
  end
end
