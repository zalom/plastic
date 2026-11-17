# frozen_string_literal: true

require_relative "../../../test_helper"

class NodeReleaseCaseTest < Plastic::TestCase
  def test_releasing_a_failed_node_opens_it_and_offers_the_claim
    alpha_with_node
    ran("node claim 1 n1", "node fail 1 n1 red")

    assert_case line("node release 1 n1"), code: 0, out: ["node: n1 open", "next: plastic node claim 1 n1"]
  end
end

class NodeReleaseTest < Plastic::TestCase
  def cli(*args) = plastic(*args, table: Plastic::CLI::TABLE, env: { "PLASTIC_SESSION" => "s-1" })

  def setup
    super
    open_keyed_intent
    cli("node", "add", "1", "a", "--criterion", "done")
  end

  def test_releasing_a_claimed_node_opens_it_and_offers_the_claim
    cli("node", "claim", "1", "n1")

    result = cli("node", "release", "1", "n1")

    assert_call result, code: 0, out: "node: n1 open\nwrote:  1 node in work_graph.db\nfiles:  store/1--alpha/graph.json\n\nnext: plastic node claim 1 n1\nbecause: node n1 is open\n"
  end

  def test_releasing_an_open_node_is_refused
    result = cli("node", "release", "1", "n1")

    assert_call result, code: 1, err: "plastic: node n1 is open; it cannot move to open\n"
  end
end
