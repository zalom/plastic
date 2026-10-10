# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/check_graph"

class CheckGraphTest < Plastic::TestCase
  def check(intent_id = "1") = run_workflow(Plastic::Workflows::CheckGraph, intent_id:)

  def specified
    write("#{open_intent.dir}/spec.md", "# Spec\n\n## Done criteria\n- It works\n")
    sync_up
  end

  def test_a_clean_graph_with_no_ready_node_has_no_findings_and_ends_with_nothing_to_offer
    specified

    outcome, context = check

    assert_equal [:nothing, ["no findings"]], [outcome, context.printed]
  end

  def test_a_clean_graph_with_a_ready_node_ends_done
    specified
    store_graphs.work.add_node(intent_id: "1", title: "a", criterion: "done")

    outcome, context = check

    assert_equal [:done, ["no findings"]], [outcome, context.printed]
  end

  def test_a_done_node_with_no_findings_is_a_finding_that_fails_the_call
    specified
    store_graphs.work.add_node(intent_id: "1", title: "a", criterion: "done", state: "done")

    outcome, context = check

    assert_equal ["finding: node n1 is done with no findings"], context.printed
    assert_equal "code_check_graph, gate: see the findings above", outcome.message
  end

  def test_an_unknown_intent_fails_the_call
    assert_equal "code_check_graph, gate: no intent 9 in this store", check("9").first.message
  end
end
