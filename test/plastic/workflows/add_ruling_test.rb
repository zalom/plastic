# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/add_ruling"

class AddRulingTest < Plastic::TestCase
  def rule(intent_id: "1", supersedes: nil) = run_workflow(Plastic::Workflows::AddRuling, intent_id:, text: "Keep it small", supersedes:)

  def test_a_ruling_is_written_and_named
    open_intent

    outcome, context = rule

    assert_equal [:done, ["ruling: D1"]], [outcome, context.printed]
    assert_equal ["Keep it small"], retrieval.rulings("1").map(&:text)
  end

  def test_an_unknown_intent_fails_with_no_ruling
    outcome, = rule(intent_id: "9")

    assert_equal "code_add_ruling, gate: no intent 9 in this store", outcome.message
  end

  def test_superseding_a_missing_ruling_fails_with_no_ruling
    open_intent

    outcome, = rule(supersedes: "D7")

    assert_equal "code_add_ruling, gate: no ruling D7 in intent 1", outcome.message
    assert_empty retrieval.rulings("1")
  end
end
