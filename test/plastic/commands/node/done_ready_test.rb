# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/node/done"

class NodeDoneReadyTest < Plastic::TestCase
  include LifecycleHelper

  def setup
    super
    specified
    cli("intent", "approve", "1")
    cli("intent", "start", "1")
  end

  def finish(node)
    cli("node", "claim", "1", node, "--agent", "tester")
    cli("node", "done", "1", node, "ok")
  end

  def test_the_nodes_now_ready_are_named_and_the_next_line_claims_the_first
    cli("node", "add", "1", "Plan", "--criterion", KEY)
    cli("node", "add", "1", "Build", "--criterion", KEY)
    cli("node", "add", "1", "Docs", "--criterion", KEY)
    cli("edge", "add", "1", "n1", "n2")
    cli("edge", "add", "1", "n1", "n3")

    assert_call finish("n1"), code: 0,
      out: ["node: n1 done", "ready: n2 Build", "ready: n3 Docs", "next: plastic node claim 1 n2 --agent NAME", "because: node n1 is done; node n2 is ready"]
  end

  def test_with_nothing_ready_the_next_line_keeps_the_graph_ready_command
    cli("node", "add", "1", "Plan", "--criterion", KEY)
    cli("node", "add", "1", "Build", "--criterion", KEY)
    cli("node", "add", "1", "Other", "--criterion", KEY)
    cli("edge", "add", "1", "n1", "n3")
    cli("edge", "add", "1", "n2", "n3")
    cli("node", "claim", "1", "n2", "--agent", "tester")

    result = finish("n1")

    refute_match(/^ready:/, result.out)
    assert_call result, code: 0, out: /next: plastic graph ready 1\nbecause: node n1 is done/
  end

  def test_when_the_intent_is_complete_the_next_line_keeps_the_graph_ready_command
    cli("node", "add", "1", "Only", "--criterion", KEY)

    result = finish("n1")

    refute_match(/^ready:/, result.out)
    assert_call result, code: 0, out: /next: plastic graph ready 1\nbecause: node n1 is done/
  end
end
