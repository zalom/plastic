# frozen_string_literal: true

require_relative "../../test_helper"

class CodeWorkflowGateTest < Plastic::TestCase
  def gate(stops, pass) = Plastic::CodeWorkflow::Gate.new(reason: "%{name} is held", stops:, pass: ->(_c) { pass }, offers: nil)

  def test_a_gate_that_holds_lets_the_call_through
    assert_nil gate(:refusal, true).run(context, Flows::Hold)
  end

  def test_a_refusal_gate_ends_the_call_with_its_filled_reason
    assert_equal Plastic::Refused.new(:code_hold, "ada is held"), gate(:refusal, false).run(context, Flows::Hold)
  end

  def test_a_failure_gate_ends_the_call_as_a_failed_gate
    assert_equal Plastic::Failed.new(:code_hold, "gate", "ada is held"), gate(:failure, false).run(context, Flows::Hold)
  end
end
