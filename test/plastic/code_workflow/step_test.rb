# frozen_string_literal: true

require_relative "../../test_helper"

class CodeWorkflowStepTest < Plastic::TestCase
  def step(done:, &body) = Plastic::CodeWorkflow::Step.new(name: "mark", done:, changes: {}, body:)

  def ctx = (@ctx ||= context(declared: %i[name mark], facts: { name: "ada" }))

  def test_a_step_already_done_skips_its_body
    ran = []

    assert_nil step(done: ->(_c) { true }) { |_c| ran << :body }.call(ctx, Flows::Stamp)
    assert_empty ran
  end

  def test_a_step_whose_body_lands_the_change_passes
    assert_nil step(done: ->(c) { c.mark }) { |c| c[:mark] = true }.call(ctx, Flows::Stamp)
  end

  def test_a_step_whose_done_check_still_fails_after_the_body_fails
    error = assert_raises(Plastic::Failed) { step(done: ->(_c) { false }) { |_c| nil }.call(ctx, Flows::Stamp) }

    assert_equal ["the step ran and its done check still fails", "code_stamp, mark"], [error.message, error.source]
  end
end
