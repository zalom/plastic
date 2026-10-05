# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/show_intent"

class WorkflowShowIntentTest < Plastic::TestCase
  def show(intent_id = "1") = run_workflow(Plastic::Workflows::ShowIntent, intent_id:)

  def test_the_intent_heading_and_criteria_count_lead
    open_intent

    printed = show.last.printed

    assert_equal ["intent: #{retrieval.intent("1").heading}", "criteria: 0"], printed.first(2)
  end

  def test_open_decisions_rulings_and_nodes_are_printed
    write("#{open_intent.dir}/spec.md", "# Spec\n\n## Open decisions\n- Which way\n")
    sync_up
    store_graphs.work.add_ruling(intent_id: "1", text: "Left")
    store_graphs.work.add_node(intent_id: "1", title: "Build")

    printed = show.last.printed

    assert_equal ["open decision: Which way", "ruling: D1 Left", "node: n1 open Build"], printed.drop(2).first(3)
  end

  def test_an_unknown_intent_fails_the_call
    assert_equal "code_show_intent, gate: no intent 9 in this store", show("9").first.message
  end
end
