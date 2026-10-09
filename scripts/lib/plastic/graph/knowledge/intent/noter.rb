# frozen_string_literal: true

require_relative "notes"
require_relative "../../retrieval/evidence/writer"

module Plastic
  module Graph
    module Knowledge
      class Intent
        # Adds one line under `## Notes` in an intent's outcome.md as a new
        # revision of that document. The old revision row stays.
        class Noter
          FILE = "outcome.md"

          def initialize(databases, retrieval, folder)
            @databases = databases
            @retrieval = retrieval
            @folder = folder
          end

          # Why the note cannot be written, or nil.
          def problem(intent, text)
            return "the note is one line; it holds a line break" if text.include?("\n")

            "#{path(intent)} changed by hand since the last print; run plastic sync up first" if edited?(intent)
          end

          # Writes the note and returns the qualified reference of the new revision.
          def write(intent, kind, text)
            id = intent.intent_id
            body = Notes.new(@retrieval.fetch(id, FILE)&.body).add(kind, text)
            Retrieval::Evidence::Writer.new(@databases.fetch(:knowledge), @retrieval.origin_id).write(id, FILE, body)
            @retrieval.reference(id, FILE).fetch(:uri)
          end

          private

          def path(intent) = "#{intent.dir}/#{FILE}"

          def edited?(intent)
            path = path(intent)
            @folder.exist?(path) && @folder.digest(path) != @retrieval.printed[path]
          end
        end
      end
    end
  end
end
