# frozen_string_literal: true

require_relative "../../test_helper"

class NodeResolveTest < Plastic::TestCase
  def cli(*args) = plastic(*args, table: Plastic::CLI::TABLE)

  def setup
    super
    open_keyed_intent
    cli("node", "add", "1", "a", "--criterion", "done")
    cli("node", "claim", "1", "n1")
  end

  def test_resolving_a_needs_info_node_opens_it_and_offers_the_claim
    cli("node", "ask", "1", "n1", "which way?")

    result = cli("node", "resolve", "1", "n1", "go left")

    assert_call result, code: 0, out: "node: n1 open\nwrote:  1 node in work_graph.db\n\nnext: plastic node claim 1 n1 --project global\nbecause: node n1 is open\n"
  end

  def test_resolving_an_impeded_node_opens_it
    cli("node", "impede", "1", "n1", "no access")

    assert_equal 0, cli("node", "resolve", "1", "n1", "access granted").code
    assert_equal "open", retrieval.node("1", "n1").state
  end

  def test_a_node_row_left_parked_by_an_older_database_resolves_and_blocks_nothing
    store_graphs.databases.fetch(:work).transaction { |batch| batch.add("UPDATE nodes SET state = 'parked' WHERE id = 'n1'") }

    result = cli("node", "resolve", "1", "n1", "go left")

    assert_equal [0, ["n1"]], [result.code, retrieval.ready_nodes("1").map(&:id)]
  end

  def test_resolving_a_claimed_node_is_refused
    result = cli("node", "resolve", "1", "n1", "go left")

    assert_call result, code: 1, err: "plastic: code_resolve_node, gate: node n1 is claimed; it cannot move to open\n"
  end
end
