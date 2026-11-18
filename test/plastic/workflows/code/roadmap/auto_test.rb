# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/workflows/code/roadmap/auto"

class WorkflowRoadmapAutoTest < Plastic::TestCase
  include DeliveryHelper
  include RoadmapHelper

  def pick(slug, session: "s-1", **facts)
    run_workflow(Plastic::Workflows::Code::Roadmap::Auto, harness: scoped_harness(session:), graphs: session_graphs, slug:, **facts)
  end

  def started(item_id) = store_graphs.work.open_roadmap_item("r1", item_id).first

  def test_an_unknown_roadmap_fails
    error = assert_raises(Plastic::Failed) { pick("r9") }

    assert_equal "no roadmap r9", error.message
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
    store_graphs.databases.fetch(:store).transaction do |batch|
      batch.write(:intents, "UPDATE intents SET status = 'parked' WHERE intent_id = :intent_id", intent_id: parked)
    end

    outcome, context = pick("r1")

    assert_equal [:ready, "b"], [outcome, context.item_id]
  end

  def hold(intent_id, session)
    store_graphs.work.add_node(intent_id:, title: "Build")
    store_graphs.work.claim_node(intent_id:, id: "n1", by: session)
  end

  def test_an_item_held_by_another_live_session_is_skipped
    roadmap
    item("a")
    hold(started("a"), "s-2")

    outcome, = pick("r1")

    assert_equal :waiting, outcome
  end

  def test_an_item_held_by_this_session_is_picked
    roadmap
    item("a")
    intent_id = started("a")
    hold(intent_id, "s-1")

    outcome, context = pick("r1")

    assert_equal [:intent, intent_id], [outcome, context.intent_id]
  end

  def test_a_ready_item_is_picked_to_open
    roadmap
    item("a")

    outcome, context = pick("r1")

    assert_equal [:ready, "a", nil], [outcome, context.item_id, context.intent_id]
  end

  def test_a_blocked_item_waits
    roadmap
    item("a")
    item("b", needs: ["a"])
    hold(started("a"), "s-2")

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

    outcome, context = pick("r1", intent_id: "99", item_id: "z")

    assert_equal [:ready, nil, "a"], [outcome, context.intent_id, context.item_id]
  end
end

# Asking which intent a roadmap picks, without running the pick.
class WorkflowRoadmapAutoIntentForTest < Plastic::TestCase
  include DeliveryHelper
  include RoadmapHelper

  PICK = Plastic::Workflows::Code::Roadmap::Auto

  def started(item_id) = store_graphs.work.open_roadmap_item("r1", item_id).first

  def picked(slug, session: "s-1") = run_workflow(PICK, harness: scoped_harness(session:), graphs: session_graphs, slug:).last

  def intent_for(slug) = PICK.intent_for(picked(slug))

  def test_the_intent_for_a_roadmap_is_its_first_free_item_in_flight
    roadmap
    item("a")
    intent_id = started("a")

    assert_equal intent_id, intent_for("r1")
  end

  def test_the_intent_for_a_missing_roadmap_is_nothing_and_raises_nothing
    _error, context = stop_workflow(PICK, harness: scoped_harness(session: "s-1"), graphs: session_graphs, slug: "r9")

    assert_nil PICK.intent_for(context)
  end

  def test_the_intent_for_a_roadmap_with_only_a_ready_item_is_nothing
    roadmap
    item("a")

    assert_nil intent_for("r1")
  end

  def test_asking_for_the_intent_writes_no_fact
    roadmap
    item("a")
    context = picked("r1")
    context[:intent_id] = nil
    PICK.intent_for(context)

    assert_nil context.intent_id
  end
end
