# frozen_string_literal: true

require_relative "../../../test_helper"

class WorkEdgeTest < Plastic::TestCase
  def edge = Plastic::Graph::Work::Edge.from_h(intent_id: "1", from: "n1", to: "n2", kind: "needs")

  def test_an_edge_touches_both_of_its_ends
    assert_equal [true, true], [edge.touches?("n1"), edge.touches?("n2")]
  end

  def test_an_edge_does_not_touch_another_node
    refute edge.touches?("n3")
  end
end
