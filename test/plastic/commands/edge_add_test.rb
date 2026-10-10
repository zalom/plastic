# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/edge_add"
require_relative "../../../scripts/lib/plastic/commands/node_add"

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
    assert_equal RUN_ROW, result.out
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
