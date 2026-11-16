# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/edge/add"
require_relative "../../../../lib/plastic/commands/node/add"

class EdgeAddCaseTest < Plastic::TestCase
  def test_an_edge_between_two_nodes_prints_it_and_offers_the_graph
    alpha_specified(TWO_CRITERIA)
    ran("node add 1 Build --criterion tests-pass", "node add 1 Test --criterion suite-green")

    assert_case line("edge add 1 n2 n1"), code: 0, out: ["edge: n2 to n1", "next: plastic graph show 1"]
  end

  def test_an_edge_from_a_node_to_itself_exits_1_and_names_the_loop
    alpha_with_node(approved: false)

    assert_case line("edge add 1 n1 n1"), code: 1, out: "", err: ["edge n1 to n1 would loop or names a missing node"]
  end

  def test_an_edge_to_a_missing_node_exits_1_and_names_the_edge
    alpha_with_node(approved: false)

    assert_case line("edge add 1 n1 n9"), code: 1, out: "", err: ["edge n1 to n9 would loop or names a missing node"]
  end

  def test_an_edge_in_a_missing_intent_exits_1_and_names_it
    assert_case line("edge add 9 n2 n1"), code: 1, out: "", err: ["no intent 9 in this store"]
  end
end

class EdgeAddTest < Plastic::TestCase
  def call(*args) = plastic("edge", "add", *args, table: Plastic::CLI::TABLE)

  def add_node(title) = plastic("node", "add", "1", title, "--criterion", "done", table: Plastic::CLI::TABLE)

  def test_a_self_edge_exits_1
    open_keyed_intent
    add_node("a")

    result = call("1", "n1", "n1")

    assert_equal 1, result.code
  end

  def test_retry_after_adding_the_missing_node_succeeds
    open_keyed_intent
    add_node("a")
    failed = call("1", "n1", "n2")

    assert_includes failed.err, "would loop or names a missing node"
    add_node("b")

    result = call("1", "n1", "n2")

    assert_equal 0, result.code
    edge = sole(store_graphs.retrieval.edges("1"))

    assert_equal ["n1", "n2"], [edge.from, edge.to]
  end

  def test_an_edge_to_a_removed_node_exits_1
    open_keyed_intent
    add_node("a")
    add_node("b")
    plastic("node", "remove", "1", "n2", table: Plastic::CLI::TABLE)

    result = call("1", "n1", "n2")

    assert_equal 1, result.code
    assert_empty result.out
    assert_equal "plastic: edge n1 to n2 would loop or names a missing node\n", result.err
  end

  def test_a_loop_exits_3_and_only_one_edge_row_exists
    open_keyed_intent
    add_node("a")
    add_node("b")
    call("1", "n1", "n2")

    result = call("1", "n2", "n1")

    assert_equal 1, result.code
    assert_equal 1, store_graphs.databases.fetch(:work).rows("SELECT * FROM edges").size
  end
end
