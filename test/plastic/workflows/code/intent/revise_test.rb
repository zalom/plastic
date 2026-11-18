# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/workflows/code/intent/revise"

class ReviseIntentTest < Plastic::TestCase
  def revise(line:, why: "after grilling") = run_workflow(Plastic::Workflows::Code::Intent::Revise, intent_id: "1", line:, why:, dry_run: true)

  def test_a_change_that_is_not_valid_stops_the_call
    open_intent

    assert_raises(Plastic::Failed) { revise(line: "two\nlines") }
  end

  def test_a_valid_change_passes_the_gate
    open_intent

    assert_nil revise(line: "Beta").last.problem
  end
end
