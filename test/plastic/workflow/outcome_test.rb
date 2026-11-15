# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/workflow"
require_relative "../../../lib/plastic/workflows/code/intent/end/prepare"

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

  def test_an_outcome_that_offers_nothing_closes_on_no_command
    assert_equal [nil, "n1 is ready"], outcome(offers: nil).closing(Facts.new("n1"))
  end

  def test_an_outcome_names_no_finding_step_unless_it_is_given_one
    assert_nil outcome.found_by
    assert_equal "read the intent", Plastic::Workflow::Outcome.new(name: :closed, check: nil, offers: nil, because: "x", stops: false, found_by: "read the intent").found_by
  end

  def test_the_prepare_step_of_intent_end_names_the_read_that_finds_a_closed_intent
    closed = Plastic::Workflows::Code::Intent::End::Prepare.outcomes.find { |each| each.name == :closed }

    assert_equal "read the intent", closed.found_by
  end

  def test_templates_leave_out_a_missing_offer
    assert_equal ["%<ready>s is ready"], outcome(offers: nil).templates
  end
end
