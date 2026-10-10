# frozen_string_literal: true

require_relative "../../command_reference_helper"

class CommandReferenceStepReadingsTest < Minitest::Test
  Workflow = Struct.new(:outcomes, :lane, :handoff_exit_code)
  Source = Struct.new(:unused) do
    def lambda_code(_callable) = nil
  end
  Owner = Struct.new(:workflow, :source) do
    def at(_callable, _word) = nil

    def named(_word, _name) = nil

    def first(_word) = ["flow.rb", 3]

    def next_key(_name) = :after
  end

  def test_an_outcome_with_no_line_reads_as_the_fallback_at_the_first_outcome_line
    owner = Owner.new(Workflow.new([], "code", 0), Source.new)
    outcome = CommandReference::OutcomeReading.new(:done, owner).outcome

    assert_equal [:done, nil, true, nil, :after, "flow.rb", 3], outcome.to_h.values_at(:name, :check, :fallback, :offers, :to, :file, :line)
  end
end
