# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/pick_delivery"

class WorkflowPickDeliveryTest < Plastic::TestCase
  include DeliveryHelper
  include RoadmapHelper

  def pick(id, session: "s-1", **facts)
    run_workflow(Plastic::Workflows::PickDelivery, harness: scoped_harness(session:), graphs: session_graphs, id:, **facts)
  end

  def started(item_id) = store_graphs.work.open_roadmap_item("r1", item_id).first

  def test_an_intent_id_is_the_intent_to_deliver
    outcome, context = pick("7")

    assert_equal [:intent, "7"], [outcome, context.intent_id]
  end

  def test_an_unknown_roadmap_fails
    outcome, = pick("r9")

    assert_equal "code_pick_delivery, gate: no roadmap r9", outcome.message
  end

  def test_the_first_in_flight_item_is_picked
    roadmap
    item("a")
    item("b")
    started("a")
    second = started("b")
    store_graphs.work.drop_item("r1", "a")

    outcome, context = pick("r1")

    assert_equal [:intent, second], [outcome, context.intent_id]
  end

  def test_a_parked_item_is_skipped
    roadmap
    item("a")
    item("b")
    parked = started("a")
    store_graphs.databases.fetch(:work).transaction do |batch|
      batch.write(:intents, "UPDATE intents SET status = 'parked' WHERE intent_id = :intent_id", intent_id: parked)
    end

    outcome, context = pick("r1")

    assert_equal [:ready, "b"], [outcome, context.ready_id]
  end

  def test_an_item_held_by_another_live_session_is_skipped
    roadmap
    item("a")
    store_graphs.work.take_lock(started("a"), session_id: "s-2", mode: "auto")

    outcome, = pick("r1")

    assert_equal :waiting, outcome
  end

  def test_an_item_held_by_this_session_is_picked
    roadmap
    item("a")
    intent_id = started("a")
    store_graphs.work.take_lock(intent_id, session_id: "s-1", mode: "auto")

    outcome, context = pick("r1")

    assert_equal [:intent, intent_id], [outcome, context.intent_id]
  end

  def test_a_ready_item_is_offered_to_start
    roadmap
    item("a")

    outcome, context = pick("r1")

    assert_equal [:ready, "a", nil], [outcome, context.ready_id, context.intent_id]
  end

  def test_a_blocked_item_waits
    roadmap
    item("a")
    item("b", after: ["a"])
    store_graphs.work.take_lock(started("a"), session_id: "s-2", mode: "auto")

    outcome, = pick("r1")

    assert_equal :waiting, outcome
  end

  def test_a_roadmap_with_every_item_dropped_is_delivered
    roadmap
    item("a")
    store_graphs.work.drop_item("r1", "a")

    outcome, = pick("r1")

    assert_equal :delivered, outcome
  end

  def test_stale_facts_are_cleared_on_every_call
    roadmap
    item("a")

    outcome, context = pick("r1", intent_id: "99", ready_id: "z")

    assert_equal [:ready, nil, "a"], [outcome, context.intent_id, context.ready_id]
  end
end
