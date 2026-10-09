# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/show_graph"

class WorkflowShowGraphTest < Plastic::TestCase
  def show(intent_id = "1") = run_workflow(Plastic::Workflows::ShowGraph, intent_id:)

  def test_each_node_and_edge_is_printed
    open_intent
    store_graphs.work.add_node(intent_id: "1", title: "Build")
    store_graphs.work.add_node(intent_id: "1", title: "Ship")
    store_graphs.work.add_edge(intent_id: "1", from: "n1", to: "n2")

    outcome, context = show

    assert_equal [:done, ["node: n1 open Build", "node: n2 open Ship", "edge: n1 to n2"]], [outcome, context.printed]
  end

  def test_an_unknown_intent_fails_the_call
    assert_equal "code_show_graph, gate: no intent 9 in this store", show("9").first.message
  end
end
