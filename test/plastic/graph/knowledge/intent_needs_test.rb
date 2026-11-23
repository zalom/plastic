# frozen_string_literal: true

require_relative "../../../test_helper"

# What an intent still waits on, read from the needs links of the store.
class KnowledgeIntentNeedsTest < Plastic::TestCase
  def needs = Plastic::Graph::Knowledge::IntentNeeds.new(store_graphs.retrieval)

  def link(from, to) = store_graphs.work.add_link(from_ref: from, to_ref: to, kind: "needs")

  def test_an_intent_waits_on_a_needed_intent_that_is_not_finished
    open_intent
    open_intent("Beta")
    link("1", "2")

    assert_equal ["2"], needs.waiting_on("1")
  end

  def test_an_intent_waits_on_a_needed_intent_the_store_does_not_hold
    open_intent
    link("1", "99")

    assert_equal ["99"], needs.waiting_on("1")
  end

  def test_the_blocked_intents_name_what_they_wait_on
    open_intent
    open_intent("Beta")
    link("1", "2")

    assert_equal({ "1" => ["2"] }, needs.blocked(store_graphs.retrieval.intents))
  end
end
