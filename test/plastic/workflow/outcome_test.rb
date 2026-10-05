# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflow"

class OutcomeTest < Minitest::Test
  Facts = Data.define(:ready) do
    def fill(template) = format(template, ready:)
  end

  def outcome(check: nil, offers: "plastic next %<ready>s")
    Plastic::Workflow::Outcome.new(name: :done, check:, offers:, because: "%<ready>s is ready", stops: false)
  end

  def test_an_outcome_with_no_check_is_the_fallback_and_always_holds
    fallback = outcome

    assert_predicate [fallback.fallback?, fallback.holds?(Facts.new("n1"))], :all?
  end

  def test_an_outcome_with_a_check_holds_only_when_the_check_does
    checked = outcome(check: ->(facts) { facts.ready == "n1" })

    assert_predicate [checked.holds?(Facts.new("n1")), !checked.holds?(Facts.new("n2"))], :all?
  end

  def test_closing_fills_the_next_and_because_lines_from_the_facts
    assert_equal ["plastic next n1", "n1 is ready"], outcome.closing(Facts.new("n1"))
  end

  def test_an_outcome_that_offers_nothing_closes_on_none
    assert_equal ["none", "n1 is ready"], outcome(offers: nil).closing(Facts.new("n1"))
  end

  def test_templates_leave_out_a_missing_offer
    assert_equal ["%<ready>s is ready"], outcome(offers: nil).templates
  end
end
