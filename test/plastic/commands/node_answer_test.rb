# frozen_string_literal: true

require_relative "../../test_helper"

class NodeAnswerTest < Plastic::TestCase
  def cli(*args) = plastic(*args, table: Plastic::CLI::TABLE)

  def setup
    super
    open_intent
    cli("node", "add", "1", "a", "--criterion", "done")
  end

  def test_answering_a_parked_node_opens_it_and_offers_the_claim
    cli("node", "claim", "1", "n1")
    cli("node", "park", "1", "n1", "--question", "which way?")

    result = cli("node", "answer", "1", "n1", "--answer", "go left")

    assert_call result, code: 0, out: "node: n1 open\nwrote:  1 node in work_graph.db\n\nnext: plastic node claim 1 n1 --project global\nbecause: node n1 is open\n"
  end

  def test_answering_an_open_node_is_refused
    result = cli("node", "answer", "1", "n1", "--answer", "go left")

    assert_call result, code: 1, err: "plastic: code_answer_node, gate: node n1 is open; it cannot move to open\n"
  end
end
