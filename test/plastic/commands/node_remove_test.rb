# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/node_remove"
require_relative "../../../scripts/lib/plastic/commands/node_add"
require_relative "../../../scripts/lib/plastic/commands/node_claim"

class NodeRemoveTest < Plastic::TestCase
  def add_node(title) = plastic("node", "add", "1", title, "--criterion", "done", table: Plastic::CLI::TABLE)

  def remove(*args) = plastic("node", "remove", *args, table: Plastic::CLI::TABLE)

  def test_removing_a_claimed_node_exits_1
    open_intent
    add_node("a")
    plastic("node", "claim", "1", "n1", table: Plastic::CLI::TABLE)

    result = remove("1", "n1")

    assert_equal 1, result.code
  end

  def test_removing_an_open_node_moves_it_to_removed
    open_intent
    add_node("a")

    result = remove("1", "n1", "--reason", "not needed")

    assert_equal 0, result.code
    assert_equal "removed", store_graphs.retrieval.node("1", "n1").state
  end
end
