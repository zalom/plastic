# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/workflows/code/intent/show"

class WorkflowShowIntentTest < Plastic::TestCase
  def show(intent_id = "1") = run_workflow(Plastic::Workflows::Code::Intent::Show, intent_id:)

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

    assert_equal ["open decision: Which way", "D1: Left", "node: n1 open Build"], printed.drop(2).first(3)
  end

  def test_ten_rulings_print_in_number_order
    open_intent
    10.times { |number| store_graphs.work.add_ruling(intent_id: "1", text: "Ruling #{number + 1}") }

    rulings = show.last.printed.grep(/\AD\d/).map { |line| line[/D\d+/] }

    assert_equal (1..10).map { |number| "D#{number}" }, rulings
  end

  def test_an_unknown_intent_fails_the_call
    assert_equal "no intent 9 in this store", assert_raises(Plastic::Failed) { show("9") }.message
  end
end
