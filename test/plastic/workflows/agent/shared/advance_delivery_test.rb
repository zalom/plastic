# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/workflows/agent/shared/advance_delivery"

class AdvanceDeliveryTest < Plastic::TestCase
  def advance(handoff_text) = run_workflow(Plastic::Workflows::Agent::Shared::AdvanceDelivery, handoff_text:, why: "the harness must plan this intent").first

  def test_a_pending_instruction_is_handed_to_the_harness
    outcome = advance("Plan intent 1.")

    assert_equal [["Plan intent 1."], "the harness must plan this intent"], [outcome.steps, outcome.because]
  end

  def test_no_pending_instruction_is_done
    assert_equal :done, advance(nil)
  end
end
