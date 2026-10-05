# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/ready_graph"

class ReadyGraphTest < Plastic::TestCase
  def ready(intent_id = "1") = run_workflow(Plastic::Workflows::ReadyGraph, intent_id:)

  def test_only_nodes_with_nothing_open_before_them_are_listed
    open_intent
    store_graphs.work.add_node(intent_id: "1", title: "Build")
    store_graphs.work.add_node(intent_id: "1", title: "Ship")
    store_graphs.work.add_edge(intent_id: "1", from: "n1", to: "n2")

    _outcome, context = ready

    assert_equal [["ready: n1 Build"], "n1"], [context.printed, context.first]
  end

  def test_an_unknown_intent_fails_the_call
    assert_equal "code_ready_graph, gate: no intent 9 in this store", ready("9").first.message
  end
end
