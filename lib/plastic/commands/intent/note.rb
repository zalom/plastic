# frozen_string_literal: true

require_relative "../../routine"
require_relative "../../graph/knowledge/intent/notes"

module Plastic
  module Commands
    module Intent
      # Adds one line to the intent's outcome.md: a note under `## Notes`, or a record of the delivery or the close
      # under `## Verification`. The earlier text stays as an earlier revision of the file.
      class Note < Routine
        intent_subject
        argument :text, label: "TEXT", text: "the note, one line"
        option :kind, switch: "--kind KIND", default: "Note",
          text: "the kind of line, in any case: Note, Review, Commit or Report under Notes; Merged, Committed, Delivered, " \
                "Pull request, Approved, Reverted or Abandoned under Verification, each in its form"
        reads :work
        writes :knowledge, :retrieval
        prints :intent

        def call
          notes = Plastic::Graph::Knowledge::Intent::Notes
          raise Usage, "KIND takes #{notes.labels.join(", ")}" unless notes.kind(parsed[:kind])

          super
        end

        workflow :code_note_intent, next: :noop
      end
    end
  end
end
