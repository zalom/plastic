# frozen_string_literal: true

require_relative "../../test_helper"

class NodeReleaseTest < Plastic::TestCase
  def cli(*args) = plastic(*args, table: Plastic::CLI::TABLE)

  def setup
    super
    open_keyed_intent
    cli("node", "add", "1", "a", "--criterion", "done")
  end

  def test_releasing_a_claimed_node_opens_it_and_offers_the_claim
    cli("node", "claim", "1", "n1")

    result = cli("node", "release", "1", "n1")

    assert_call result, code: 0, out: "node: n1 open\nwrote:  1 routine run in local.db\n        1 node in work_graph.db\nfiles:  store/1--alpha/graph.json\n\nnext: plastic node claim 1 n1\nbecause: node n1 is open\n"
  end

  def test_releasing_an_open_node_is_refused
    result = cli("node", "release", "1", "n1")

    assert_call result, code: 1, out: RUN_ROW, err: "plastic: node n1 is open; it cannot move to open\n"
  end
end
