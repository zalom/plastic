# frozen_string_literal: true

require_relative "../../test_helper"

class NodeParkTest < Plastic::TestCase
  def cli(*args) = plastic(*args, table: Plastic::CLI::TABLE)

  def setup
    super
    open_intent
    cli("node", "add", "1", "a", "--criterion", "done")
  end

  def test_parking_a_claimed_node_offers_the_answer
    cli("node", "claim", "1", "n1")

    result = cli("node", "park", "1", "n1", "--question", "which way?")

    assert_call result, code: 0,
      out: "node: n1 parked\nwrote:  1 node in work_graph.db\n\nnext: plastic node answer 1 n1 --answer TEXT --project global\nbecause: node n1 is parked\n"
  end

  def test_parking_an_open_node_is_refused
    result = cli("node", "park", "1", "n1", "--question", "which way?")

    assert_call result, code: 1, err: "plastic: code_park_node, gate: node n1 is open; it cannot move to parked\n"
  end
end
