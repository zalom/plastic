# frozen_string_literal: true

require_relative "../../test_helper"

class CodeWorkflowGateTest < Plastic::TestCase
  def gate(stops, pass) = Plastic::CodeWorkflow::Gate.new(reason: "%{name} is held", stops:, pass: ->(_c) { pass }, offers: nil, because: nil)

  def test_a_gate_that_holds_lets_the_call_through
    assert_nil gate(:refusal, true).call(context, Flows::Hold)
  end

  def test_a_refusal_gate_ends_the_call_with_its_filled_reason
    error = assert_raises(Plastic::Refused) { gate(:refusal, false).call(context, Flows::Hold) }

    assert_equal ["ada is held", "code_hold, gate"], [error.message, error.source]
  end

  def test_a_failure_gate_ends_the_call_as_a_failed_gate
    error = assert_raises(Plastic::Failed) { gate(:failure, false).call(context, Flows::Hold) }

    assert_equal ["ada is held", "code_hold, gate"], [error.message, error.source]
  end

  def test_a_gate_with_a_because_line_ends_the_call_with_it
    held = Plastic::CodeWorkflow::Gate.new(reason: "%{name} is held", stops: :failure, pass: ->(_c) { false }, offers: nil, because: "%{name} waits")

    error = assert_raises(Plastic::Failed) { held.call(context, Flows::Hold) }

    assert_equal ["ada is held", "ada waits"], [error.message, error.because]
  end
end
