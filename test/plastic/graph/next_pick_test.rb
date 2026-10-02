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
