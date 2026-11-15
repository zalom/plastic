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

  def reading(line) = CommandReference::OutcomeReading.new(:done, Owner.new(Workflow.new([line], "code", 0), Source.new)).outcome

  def line(because, ends_when = nil) = Plastic::Workflow::Outcome.new(name: :done, check: ->(_c) { true }, offers: "next", because:, stops: nil, ends_when:)

  def test_an_outcome_line_gives_its_offer_and_its_found_by_to_the_outcome
    outcome = reading(line("it ended"))

    assert_equal ["next", false, nil, nil], outcome.to_h.values_at(:offers, :fallback, :found_by, :unreachable)
  end

  def test_an_outcome_whose_because_is_only_a_placeholder_reads_the_words_of_ends_when
    assert_equal "the call ended", reading(line("%{why}", "the call ended")).because
  end

  def test_an_outcome_whose_because_is_a_sentence_keeps_it_even_with_ends_when
    assert_equal "it ended", reading(line("it ended", "other words")).because
  end
end
