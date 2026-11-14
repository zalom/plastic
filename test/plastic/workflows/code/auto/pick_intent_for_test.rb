# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/workflows/code/auto/pick"

# Asking which intent a word picks, without running the pick.
class WorkflowPickIntentForTest < Plastic::TestCase
  include DeliveryHelper
  include RoadmapHelper

  PICK = Plastic::Workflows::Code::Auto::Pick

  def started(item_id) = store_graphs.work.open_roadmap_item("r1", item_id).first

  def picked(id, session: "s-1") = run_workflow(PICK, harness: scoped_harness(session:), graphs: session_graphs, id:).last

  def intent_for(id) = PICK.intent_for(picked(id))

  def test_the_intent_for_an_intent_word_is_that_intent
    assert_equal "7", intent_for("7")
  end

  def test_the_intent_for_a_roadmap_is_its_first_free_item_in_flight
    roadmap
    item("a")
    intent_id = started("a")

    assert_equal intent_id, intent_for("r1")
  end

  def test_the_intent_for_a_missing_roadmap_is_nothing_and_raises_nothing
    assert_nil intent_for("r9")
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
