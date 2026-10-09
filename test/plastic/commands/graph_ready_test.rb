# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/graph_ready"
require_relative "../../../scripts/lib/plastic/commands/node_add"
require_relative "../../../scripts/lib/plastic/commands/edge_add"

class GraphReadyTest < Plastic::TestCase
  def call(*args) = plastic("graph", "ready", *args, table: Plastic::CLI::TABLE)

  def add_node(title) = plastic("node", "add", "1", title, "--criterion", "done", table: Plastic::CLI::TABLE)

  def two_linked_nodes
    open_keyed_intent
    add_node("a")
    add_node("b")
    plastic("edge", "add", "1", "n1", "n2", table: Plastic::CLI::TABLE)
  end

  def test_an_open_node_with_no_need_is_ready
    open_keyed_intent
    add_node("a")

    result = call("1")

    assert_equal 0, result.code
    assert_includes result.out, "ready: n1 a"
    assert_includes result.out.lines(chomp: true), "next: plastic node claim 1 n1"
  end

  def test_a_node_whose_need_is_not_done_is_not_ready
    two_linked_nodes

    result = call("1")

    assert_call result, code: 0, out: ["ready: n1 a"]
    refute_includes result.out, "ready: n2 b"
  end

  def test_claimed_work_leaves_nothing_ready_and_no_next_line
    two_linked_nodes
    plastic("node", "claim", "1", "n1", table: Plastic::CLI::TABLE)
    plastic("node", "done", "1", "n1", "ok", table: Plastic::CLI::TABLE)
    plastic("node", "claim", "1", "n2", table: Plastic::CLI::TABLE)

    result = call("1")

    assert_equal [0, ""], [result.code, result.err]
    refute_match(/^next:/, result.out)
    assert_includes result.out, "because: no node is ready to claim"
    refute_includes result.out, "ready:"
  end
end
