# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/workflows/code/intent/judge"

class JudgeIntentTest < Plastic::TestCase
  def judge = run_workflow(Plastic::Workflows::Code::Intent::Judge, intent_id: "1")

  def test_a_done_intent_stops_the_call
    open_intent(status: "done")

    assert_raises(Plastic::Failed) { judge }
  end

  def test_an_open_intent_passes_the_gate
    open_intent

    assert_nil judge.last.problem
  end
end
