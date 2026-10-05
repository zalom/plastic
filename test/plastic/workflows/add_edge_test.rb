# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/add_edge"

class AddEdgeTest < Plastic::TestCase
  def setup
    super
    open_intent
    %w[a b].each { |title| store_graphs.work.add_node(intent_id: "1", title:, criterion: "done") }
  end

  def add(from, to, intent_id: "1") = run_workflow(Plastic::Workflows::AddEdge, intent_id:, from:, to:)

  def test_an_edge_between_two_nodes_is_written_and_named
    outcome, context = add("n1", "n2")

    assert_equal [:done, ["edge: n1 to n2"]], [outcome, context.printed]
    assert_equal [%w[n1 n2]], retrieval.edges("1").map { |edge| [edge.from, edge.to] }
  end

  def test_an_unknown_intent_fails_with_no_edge
    outcome, = add("n1", "n2", intent_id: "9")

    assert_equal "code_add_edge, gate: no intent 9 in this store", outcome.message
    assert_empty retrieval.edges
  end

  def test_a_self_edge_fails_with_no_edge
    outcome, = add("n1", "n1")

    assert_equal "code_add_edge, gate: edge n1 to n1 would loop or names a missing node", outcome.message
    assert_empty retrieval.edges("1")
  end

  def test_a_refused_edge_is_tried_again_on_the_next_call
    context = Plastic::Context.new(declared: Plastic::Workflows::AddEdge.facts + %i[intent_id from to],
      facts: { intent_id: "1", from: "n1", to: "n2", added: false }, graphs: store_graphs)

    assert_equal :done, Plastic::Workflows::AddEdge.call(context)
    assert_equal 1, retrieval.edges("1").size
  end
end
