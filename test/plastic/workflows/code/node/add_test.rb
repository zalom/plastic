# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/workflows/code/node/add"

class AddNodeTest < Plastic::TestCase
  def add(intent_id: "1") = run_workflow(Plastic::Workflows::Code::Node::Add, intent_id:, title: "Build", criterion: "runs", kind: nil, input: nil, found_in: nil, deadline: nil)

  def test_a_node_is_written_open_and_named
    open_keyed_intent(key: "runs")

    outcome, context = add

    assert_equal [:done, ["node: n1"]], [outcome, context.printed]
    assert_equal [%w[n1 open Build]], retrieval.structure.nodes("1").map { |node| [node.id, node.state, node.title] }
  end

  def test_an_unknown_intent_fails_with_no_node
    error = assert_raises(Plastic::Failed) { add(intent_id: "9") }

    assert_equal "no intent 9 in this store", error.message
    assert_empty retrieval.structure.nodes
  end

  def test_a_done_intent_takes_no_nodes
    open_intent(status: "done")

    error = assert_raises(Plastic::Refused) { add }

    assert_equal "intent 1 is done; it takes no nodes", error.message
    assert_empty retrieval.structure.nodes("1")
  end
end
