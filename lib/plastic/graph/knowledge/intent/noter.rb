# frozen_string_literal: true

require_relative "notes"
require_relative "../../retrieval/evidence/writer"

module Plastic
  module Graph
    module Knowledge
      class Intent
        # Adds one line under Notes in an intent outcome as a new document revision.
        class Noter
          FILE = "outcome.md"

          def initialize(databases, retrieval)
            @databases = databases
            @retrieval = retrieval
          end

          def problem(text) = ("the note is one line; it holds a line break" if text.include?("\n"))

          def write(intent, kind, text)
            id = intent.intent_id
            body = Notes.for(@retrieval.fetch(id, FILE)&.body).add(kind, text)
            Retrieval::Evidence::Writer.new(@databases.fetch(:knowledge), @retrieval.origin_id).write(id, FILE, body)
            @retrieval.reference(id, FILE).fetch(:uri)
          end
        end
      end
    end
  end
end
