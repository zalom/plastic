# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/workflows/code/intent/note"

class NoteIntentTest < Plastic::TestCase
  def test_the_outcome_offers_plastic_next_and_says_the_outcome_holds_the_note
    outcome = Plastic::Workflows::Code::Intent::Note.outcomes.first

    assert_equal [:done, "plastic next", "the outcome holds the note"], [outcome.name, outcome.offers, outcome.because]
  end

  def test_a_note_with_a_line_break_stops_the_call_naming_the_problem
    open_intent

    assert_raises(Plastic::Failed) { run_workflow(Plastic::Workflows::Code::Intent::Note, intent_id: "1", kind: "note", text: "two\nlines") }
  end

  def test_a_valid_note_passes_the_gate_and_is_written
    open_intent

    outcome, context = run_workflow(Plastic::Workflows::Code::Intent::Note, intent_id: "1", kind: "note", text: "A line")

    assert_equal [:done, nil], [outcome, context.problem]
  end
end
