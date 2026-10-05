# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/graph_show"
require_relative "../../../scripts/lib/plastic/commands/node_add"
require_relative "../../../scripts/lib/plastic/commands/edge_add"

class GraphShowTest < Plastic::TestCase
  def call(*args) = plastic("graph", "show", *args, table: Plastic::CLI::TABLE)

  def add_node(title) = plastic("node", "add", "1", title, "--criterion", "done", table: Plastic::CLI::TABLE)

  def graph_path(intent) = store_path("#{intent.dir}/graph.json")

  def test_prints_each_node_and_edge
    open_intent
    add_node("a")
    add_node("b")
    plastic("edge", "add", "1", "n1", "n2", table: Plastic::CLI::TABLE)

    result = call("1")

    assert_call result, code: 0, out: ["node: n1 open a", "edge: n1 to n2"]
  end

  def test_a_hand_edited_graph_json_is_overwritten_from_rows
    intent = open_intent
    add_node("a")
    File.write(graph_path(intent), '{"bogus":true}')

    call("1")

    written = JSON.parse(File.read(graph_path(intent)))

    refute written.key?("bogus")
    assert_equal 1, written.fetch("nodes").size
  end
end
