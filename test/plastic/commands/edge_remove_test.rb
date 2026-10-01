# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/edge_remove"
require_relative "../../../scripts/lib/plastic/commands/edge_add"
require_relative "../../../scripts/lib/plastic/commands/node_add"

class EdgeRemoveTest < Plastic::TestCase
  def add_node(title) = plastic("node", "add", "1", title, "--criterion", "done", table: Plastic::CLI::TABLE)

  def test_a_missing_edge_exits_1
    open_intent
    add_node("a")
    add_node("b")

    result = plastic("edge", "remove", "1", "n1", "n2", table: Plastic::CLI::TABLE)

    assert_equal 1, result.code
  end

  def test_removing_an_existing_edge_succeeds
    open_intent
    add_node("a")
    add_node("b")
    plastic("edge", "add", "1", "n1", "n2", table: Plastic::CLI::TABLE)

    result = plastic("edge", "remove", "1", "n1", "n2", table: Plastic::CLI::TABLE)

    assert_equal 0, result.code
    assert_empty store_graphs.databases.fetch(:work).rows("SELECT * FROM edges")
  end
end
