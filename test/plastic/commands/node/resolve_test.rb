# frozen_string_literal: true

require_relative "../../../test_helper"

class NodeResolveCaseTest < Plastic::TestCase
  def test_resolving_a_node_that_is_open_exits_1_and_names_its_status
    alpha_with_node(approved: false)

    assert_case line('node resolve 1 n1 "Claude Code"'), code: 1, out: "", err: ["node n1 is open; it cannot move to open"]
  end
end

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

    assert_call result, code: 0, out: "node: n1 open\nwrote:  1 node in work_graph.db\nfiles:  store/1--alpha/graph.json\n\nnext: plastic node claim 1 n1\nbecause: node n1 is open\n"
  end

  def test_an_answer_that_holds_column_names_is_stored_unchanged
    cli("node", "ask", "1", "n1", "which way?")
    cli("node", "resolve", "1", "n1", "see :id and :intent_id")

    assert_equal "see :id and :intent_id", retrieval.node("1", "n1").answer
  end

  def test_resolving_an_impeded_node_opens_it
    cli("node", "impede", "1", "n1", "no access")

    result = cli("node", "resolve", "1", "n1", "access granted")

    assert_call result, code: 0, err: "", out: ["node: n1 open", "next: plastic node claim 1 n1"]
    assert_equal "open", retrieval.node("1", "n1").state
  end

  def test_a_node_row_left_parked_by_an_older_database_resolves_and_blocks_nothing
    store_graphs.databases.fetch(:work).transaction { |batch| batch.add("UPDATE nodes SET state = 'parked' WHERE id = 'n1'") }

    result = cli("node", "resolve", "1", "n1", "go left")

    assert_equal [0, ["n1"]], [result.code, retrieval.ready_nodes("1").map(&:id)]
  end

  def test_resolving_a_claimed_node_is_refused
    result = cli("node", "resolve", "1", "n1", "go left")

    assert_call result, code: 1, err: "plastic: node n1 is claimed; it cannot move to open\n"
  end
end
