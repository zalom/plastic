# frozen_string_literal: true

require_relative "notes"
require_relative "document_writer"
require_relative "../../../layout"

module Plastic
  module Graph
    module Knowledge
      class Intent
        # Adds one line under Notes in an intent outcome as a new document revision.
        class Noter
          FILE = Layout.name(:outcome)

          def initialize(databases, retrieval)
            @databases = databases
            @retrieval = retrieval
          end

          def self.problem(text) = ("the note is one line; it holds a line break" if text.include?("\n"))

          def write(intent, kind, text)
            id = intent.intent_id
            body = Notes.for(@retrieval.fetch(id, FILE)&.body).add(kind, text)
            DocumentWriter.new(@databases, @retrieval).write(id, FILE, body)
          end
        end
      end
    end
  end
end
