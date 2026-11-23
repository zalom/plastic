# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/workflows/code/intent/approve"

class ApproveGraphTest < Plastic::TestCase
  def setup
    super
    @intent = open_intent
    write("#{@intent.dir}/spec.md", "## Done criteria\n- It works\n")
    sync_up
    @work = store_graphs.work
  end

  def approve = run_workflow(Plastic::Workflows::Code::Intent::Approve, harness: scoped_harness(session: "s-1"), intent_id: "1")

  def test_approving_prints_the_findings_of_the_graph_and_still_approves
    2.times { |index| @work.add_node(intent_id: "1", title: "Node #{index}", criterion: "it runs") }
    outcome, context = approve

    assert_equal :done, outcome
    assert_includes context.printed, "finding: the graph has 2 nodes and no edge at all"
    refute_nil retrieval.structure.approval("1")
  end

  def test_approving_prints_the_hand_edit_of_a_finding_with_no_command
    @work.add_node(intent_id: "1", title: "Build", criterion: "it runs")
    @work.claim_node(intent_id: "1", id: "n1", by: "a")
    @work.done_node(intent_id: "1", id: "n1", findings: " ")

    assert_includes approve.last.printed, "hand edit: edit the findings of node n1 in graph.json, then run plastic sync up and plastic graph check 1 again"
  end

  def test_approving_an_intent_with_no_node_prints_no_finding
    assert_empty approve.last.printed.grep(/\Afinding:/)
  end
end
