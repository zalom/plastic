# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/done_node"

class WorkflowDoneNodeTest < Plastic::TestCase
  def setup
    super
    open_intent
    store_graphs.work.add_node(intent_id: "1", title: "Build", criterion: "it runs")
    store_graphs.work.claim_node(intent_id: "1", id: "n1", by: "s-1")
  end

  def finish(repair: nil, judge: "tests")
    run_workflow(Plastic::Workflows::DoneNode, intent_id: "1", id: "n1", judge:, findings: "green", repair:).first
  end

  def node = retrieval.node("1", "n1")

  def test_a_claimed_node_is_done_with_its_judge_and_findings
    outcome = finish

    assert_equal [:done, "done", "tests", "green"], [outcome, node.state, node.judge, node.findings]
  end

  def test_a_done_node_is_repaired_with_a_new_judge
    finish

    finish(repair: true, judge: "owner")

    assert_equal "owner", node.judge
  end

  def test_a_done_node_without_repair_is_refused
    finish

    assert_equal "code_done_node, gate: node n1 is done; it cannot move to done", finish.message
  end
end
