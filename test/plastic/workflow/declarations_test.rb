# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/workflow"

class DeclarationsTest < Plastic::TestCase
  def declaring
    Class.new(Plastic::Workflow) do
      def self.name = "Declared"
    end
  end

  def test_facts_summary_and_outcomes_are_kept_until_cleared
    workflow = declaring
    workflow.sets(:a, :b)
    workflow.summary("says it")
    workflow.outcome(:done, because: "it is done")
    kept = [workflow.facts.dup, workflow.summary, workflow.outcomes.map(&:name)]
    workflow.clear_declarations

    assert_equal [[:a, :b], "says it", [:done]], kept
    assert_equal [[], nil, []], [workflow.facts, workflow.summary, workflow.outcomes]
  end

  def test_an_unknown_outcome_option_is_refused_by_name
    error = assert_raises(Plastic::Invalid) { declaring.outcome(:done, colour: "red") }

    assert_equal "Declared: outcome done does not take colour", error.message
  end

  def test_the_ending_is_the_outcome_that_gives_its_because_line
    workflow = declaring
    workflow.outcome(:done)
    workflow.outcome(:done, because: "it is done")

    assert_equal ["it is done"], [workflow.ending(:done).because]
    assert_nil workflow.ending(:missing)
  end
end
