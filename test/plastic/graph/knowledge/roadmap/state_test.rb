# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../scripts/lib/plastic/graph/knowledge/roadmap/state"

class StateTest < Minitest::Test
  Item = Data.define(:roadmap, :item, :intent_id, :mark, :dropped) do
    def dropped? = dropped
  end
  Intent = Data.define(:status)
  Edge = Data.define(:from, :to)
  Reads = Data.define(:items, :edges, :intents) do
    def roadmap_items(_roadmap) = items
    def roadmap_edges(_roadmap) = edges
    def intent(intent_id) = intents[intent_id]
  end

  def item(name, intent_id: nil, mark: nil, dropped: false) = Item.new("r1", name, intent_id, mark, dropped)

  def state(target, items: [target], edges: [], intents: {})
    Plastic::Graph::Knowledge::Roadmap::State.of(target, Reads.new(items, edges, intents))
  end

  def test_an_item_whose_intent_is_done_is_done
    assert_equal "done", state(item("a", intent_id: "1"), intents: { "1" => Intent.new("done") })
  end

  def test_an_item_with_no_intent_is_done_by_its_delivered_mark
    assert_equal "done", state(item("a", mark: "delivered"))
  end

  def test_a_dropped_item_is_dropped
    assert_equal "dropped", state(item("a", dropped: true))
  end

  def test_an_item_whose_intent_is_open_is_in_flight
    assert_equal "in flight", state(item("a", intent_id: "1"), intents: { "1" => Intent.new("parked") })
  end

  def test_an_item_after_an_unresolved_predecessor_is_blocked
    first = item("a")
    second = item("b")

    assert_equal "blocked", state(second, items: [first, second], edges: [Edge.new("a", "b")])
  end

  def test_an_item_after_a_dropped_predecessor_is_ready
    first = item("a", dropped: true)
    second = item("b")

    assert_equal "ready", state(second, items: [first, second], edges: [Edge.new("a", "b")])
  end
end
