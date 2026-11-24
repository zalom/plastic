# frozen_string_literal: true

require_relative "../intent"
require_relative "outcome_section"
require_relative "../outcome_form"

module Plastic
  module Graph
    module Knowledge
      class Intent
        # The kinds of line `plastic intent note` adds to an intent outcome, each under its section: the notes of the
        # work under Notes, and the records of its delivery and its close under Verification.
        class Notes
          Kind = Data.define(:label, :heading)

          NOTE_LABELS = %w[Review Commit Report].freeze
          VERIFICATION_LABELS = ["Merged", "Committed", "Delivered", "Pull request", "Approved", "Reverted", "Abandoned"].freeze
          KINDS = [*NOTE_LABELS.map { |label| Kind.new(label:, heading: "## Notes") },
            *VERIFICATION_LABELS.map { |label| Kind.new(label:, heading: "## Verification") }].freeze

          # The kind a word names, matched without regard to case, else nil.
          def self.kind(word) = KINDS.find { |kind| kind.label.casecmp?(word.to_s.strip) }

          def self.labels = KINDS.map(&:label)

          # Why `text` cannot be a line of `label`: a line break, or a Verification line out of its form; else nil.
          def self.problem(label, text)
            return "the note is one line; it holds a line break" if text.include?("\n")

            "the #{label} line takes the form #{OutcomeForm.shown_forms(label)}" if OutcomeForm.formed?(label) && !OutcomeForm.in_form?(label, text)
          end

          def self.for(body, kind) = new(OutcomeSection.for(body, kind.heading), kind)

          def initialize(section, kind)
            @section = section
            @kind = kind
          end

          def add(text) = @section.add("- #{@kind.label}: #{text}")
        end
      end
    end
  end
end
