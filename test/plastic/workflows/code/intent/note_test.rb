# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/workflows/code/intent/note"

class NoteIntentTest < Plastic::TestCase
  def test_the_outcome_offers_plastic_next_and_says_the_outcome_holds_the_note
    outcome = Plastic::Workflows::Code::Intent::Note.outcomes.first

    assert_equal [:done, "plastic next", "the outcome holds the note"], [outcome.name, outcome.offers, outcome.because]
  end
end
