# frozen_string_literal: true

require_relative "../../../../../test_helper"
require_relative "../../../../../../lib/plastic/workflows/code/intent/verdict/prepare"

class VerdictPrepareTest < Plastic::TestCase
  def prepare = run_workflow(Plastic::Workflows::Code::Intent::Verdict::Prepare, intent_id: "1", verdict: "revise")

  def test_a_done_intent_stops_the_call
    open_intent(status: "done")

    assert_raises(Plastic::Failed) { prepare }
  end

  def test_an_open_intent_passes_the_gate
    open_intent

    assert_nil prepare.last.problem
  end
end
