# frozen_string_literal: true

require_relative "../../test_helper"

class AgentWorkflowStepTest < Plastic::TestCase
  def step(done) = Plastic::AgentWorkflow::Step.new(name: "write", done: ->(_c) { done }, say: "Write the note for %{name}")

  def test_a_step_not_done_is_left
    assert step(false).left?(context)
  end

  def test_a_done_step_is_not_left
    refute step(true).left?(context)
  end

  def test_the_instruction_fills_the_facts
    assert_equal "Write the note for ada", step(false).instruction(context)
  end
end
