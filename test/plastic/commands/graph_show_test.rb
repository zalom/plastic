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
    open_keyed_intent
    add_node("a")
    add_node("b")
    plastic("edge", "add", "1", "n1", "n2", table: Plastic::CLI::TABLE)

    result = call("1")

    assert_call result, code: 0, out: ["node: n1 open a", "edge: n1 to n2"]
  end

  def test_a_hand_edited_graph_json_survives_the_call_and_no_row_is_added
    intent = open_keyed_intent
    add_node("a")
    File.write(graph_path(intent), '{"bogus":true}')
    before = run_count

    result = call("1")

    assert_equal '{"bogus":true}', File.read(graph_path(intent))
    assert_equal before, run_count
    assert_equal "", result.out.lines.grep(/^wrote:/).join
  end

  def run_count = store_graphs.databases.fetch(:local).row("SELECT count(*) AS n FROM routine_runs").fetch("n")
end
