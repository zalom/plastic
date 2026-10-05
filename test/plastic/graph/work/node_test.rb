# frozen_string_literal: true

require_relative "../../../test_helper"

class WorkNodeTest < Plastic::TestCase
  def node(id, state) = Plastic::Graph::Work::Node.from_h(intent_id: "1", id:, state:)

  def test_a_refusal_names_the_node_its_state_and_the_move
    assert_equal "node n1 is done; it cannot move to claimed", node("n1", "done").refusal("claimed")
  end

  def test_an_open_node_missing_from_the_ready_nodes_is_waiting
    assert node("n2", "open").waiting?([node("n1", "open")])
  end

  def test_an_open_node_among_the_ready_nodes_is_not_waiting
    refute node("n1", "open").waiting?([node("n1", "open")])
  end

  def test_a_node_that_is_not_open_is_never_waiting
    refute node("n1", "claimed").waiting?([])
  end
end
