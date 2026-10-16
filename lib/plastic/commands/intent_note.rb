# frozen_string_literal: true

require_relative "../routine"
require_relative "../graph/knowledge/intent/notes"

module Plastic
  module Commands
    # Adds one line under `## Notes` in the intent's outcome.md. The earlier
    # text stays as an earlier revision of the file.
    class IntentNote < Routine
      intent_subject
      argument :text, label: "TEXT", text: "the note, one line"
      option :kind, switch: "--kind KIND", default: "Report", text: "Review, Commit or Report"
      reads :work
      writes :knowledge
      prints :intent

      def call
        kinds = Graph::Knowledge::Intent::Notes::KINDS
        raise CLI::Command::Usage, "KIND takes #{kinds.join(", ")}" unless kinds.include?(parsed[:kind])

        super
      end

      workflow :code_note_intent, next: :noop
    end
  end
end
