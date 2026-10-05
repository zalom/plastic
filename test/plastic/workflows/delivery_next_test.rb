# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/delivery_next"

class DeliveryNextTest < Plastic::TestCase
  def setup
    super
    open_intent
  end

  def next_action = run_workflow(Plastic::Workflows::DeliveryNext, intent_id: "1")

  def test_a_ready_node_ends_on_its_claim_command
    store_graphs.work.add_node(intent_id: "1", title: "Build")

    outcome, context = next_action

    assert_equal [:done, "plastic node claim 1 n1", "node n1 is ready"], [outcome, context.next_command, context.why]
  end

  def test_an_intent_with_no_node_needs_the_agent
    outcome, context = next_action

    assert_equal :agent_needed, outcome
    assert_includes context.handoff_text, "plastic node add 1 TITLE --criterion TEXT"
  end
end
