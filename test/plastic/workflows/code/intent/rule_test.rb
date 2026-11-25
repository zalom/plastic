# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/workflows/code/intent/rule"

class AddRulingTest < Plastic::TestCase
  def rule(intent_id: "1", text: "Keep it small", adds: nil, rewrites: nil) = run_workflow(Plastic::Workflows::Code::Intent::Rule, intent_id:, text:, adds:, rewrites:)

  def test_a_ruling_is_written_and_named
    open_intent

    outcome, context = rule

    assert_equal [:done, ["D1: Keep it small"]], [outcome, context.printed]
    assert_equal ["Keep it small"], retrieval.rulings("1").map(&:text)
  end

  def test_an_addition_is_written_under_its_decision
    open_intent
    rule

    assert_equal ["D1.1: Under a page"], rule(text: "Under a page", adds: "D1").last.printed
  end

  def test_a_rewrite_names_the_additions_it_removed
    open_intent
    rule
    rule(text: "Under a page", adds: "D1")
    rule(text: "In one file", adds: "D1")
    rule(text: "Three files", adds: "D1")

    assert_equal ["D1: Keep it smaller", "removed: the additions D1.1, D1.2 and D1.3"], rule(text: "Keep it smaller", rewrites: "D1").last.printed
  end

  def test_a_rewrite_names_the_one_addition_it_removed
    open_intent
    rule
    rule(text: "Under a page", adds: "D1")

    assert_equal ["D1: Keep it smaller", "removed: the addition D1.1"], rule(text: "Keep it smaller", rewrites: "D1").last.printed
  end

  def test_an_unknown_intent_fails_with_no_ruling
    error = assert_raises(Plastic::Failed) { rule(intent_id: "9") }

    assert_equal "no intent 9 in this store", error.message
  end

  def test_adding_to_a_missing_decision_fails_with_no_ruling
    open_intent

    error = assert_raises(Plastic::Failed) { rule(adds: "D7") }

    assert_equal "no decision D7 in intent 1", error.message
    assert_empty retrieval.rulings("1")
  end
end
