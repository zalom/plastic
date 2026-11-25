# frozen_string_literal: true

require_relative "notes"
require_relative "document_writer"
require_relative "../../../layout"

module Plastic
  module Graph
    module Knowledge
      class Intent
        # Adds one line of a note kind to its section of an intent outcome, Notes or Verification, as a new document
        # revision.
        class Noter
          FILE = Layout.name(:outcome)

          def initialize(databases, retrieval)
            @databases = databases
            @retrieval = retrieval
          end

          def self.problem(label, text) = Notes.problem(label, text)

          def write(intent, label, text)
            id = intent.intent_id
            body = Notes.for(@retrieval.fetch(id, FILE)&.body, Notes.kind(label)).add(text)
            DocumentWriter.new(@databases, @retrieval).write(id, FILE, body)
          end
        end
      end
    end
  end
end
