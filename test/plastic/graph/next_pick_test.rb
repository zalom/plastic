# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/graph/next_pick"

class NextPickTest < Plastic::TestCase
  def test_two_open_intents_pick_none
    open_intent("Alpha")
    open_intent("Beta")

    assert_nil Plastic::Graph::NextPick.new(store_graphs.retrieval, "s-1").intent
  end
end

class ClosedIntentPickTest < Plastic::TestCase
  def test_a_closed_intent_is_not_selected_through_a_leftover_lock
    intent = open_intent(status: "done")
    store_graphs.work.take_lock(intent.intent_id, session_id: "s-1", mode: "auto")

    assert_nil Plastic::Graph::NextPick.new(retrieval, "s-1").intent
  end
end
