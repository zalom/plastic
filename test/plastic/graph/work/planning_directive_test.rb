# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/work/delivery_action"

class PlanningDirectiveEdgeMeaningTest < Plastic::TestCase
  MEANING = "An edge FROM TO means TO reads, changes or tests what FROM makes. " \
    "Nodes with no path between them may run at the same time. A red test node comes before the code it tests."

  def test_the_directive_holds_the_edge_meaning_in_three_sentences
    assert_equal MEANING, Plastic::Graph::Work::PlanningDirective::EDGE_MEANING
  end

  def test_the_planning_instruction_carries_the_edge_meaning_and_sends_the_agent_to_graph_check
    work = store_graphs.work
    work.write_intent(title: "Alpha")
    work.activate_intent("1")
    instructions = Plastic::Graph::Work::DeliveryAction.new(retrieval, "1").call.last

    assert_includes instructions, MEANING
    assert_includes instructions, "Run plastic graph check 1 after the edges"
  end

  def test_the_planner_agent_carries_the_edge_meaning_and_names_graph_check
    text = File.read(File.expand_path("../../../../agents/plastic-planner.md", __dir__))

    assert_includes text, MEANING
    assert_includes text, "plastic graph check"
  end

end
