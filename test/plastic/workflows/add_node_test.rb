# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/add_node"

class AddNodeTest < Plastic::TestCase
  def add(intent_id: "1") = run_workflow(Plastic::Workflows::AddNode, intent_id:, title: "Build", criterion: "it runs", input: nil)

  def test_a_node_is_written_open_and_named
    open_intent

    outcome, context = add

    assert_equal [:done, ["node: n1"]], [outcome, context.printed]
    assert_equal [%w[n1 open Build]], retrieval.nodes("1").map { |node| [node.id, node.state, node.title] }
  end

  def test_an_unknown_intent_fails_with_no_node
    outcome, = add(intent_id: "9")

    assert_equal "code_add_node, gate: no intent 9 in this store", outcome.message
    assert_empty retrieval.nodes
  end

  def test_a_done_intent_takes_no_nodes
    open_intent(status: "done")

    outcome, = add

    assert_equal "code_add_node, gate: intent 1 is done; it takes no nodes", outcome.message
    assert_empty retrieval.nodes("1")
  end
end
