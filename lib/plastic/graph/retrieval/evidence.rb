# frozen_string_literal: true

require_relative "reference"
require_relative "maintenance"

module Plastic
  module Graph
    module Retrieval
      # Reads, repairs, and searches the retrieval evidence in one store.
      class Evidence
        DOCUMENT_SQL = "SELECT * FROM documents WHERE intent_id = :intent_id AND path = :path AND origin_id = :origin"

        def initialize(databases, store:, origin:)
          @databases = databases
          @origin = origin
          @references = Reference.new(databases, store:, origin:)
          @maintenance = Maintenance.new(databases, origin)
        end

        def documents(intent_id = nil) = @maintenance.ready_documents { read_documents(intent_id) }

        def fetch(intent_id, path) = @maintenance.ready_documents { document(intent_id, path) }

        def fetch_reference(reference) = references.fetch(reference)

        def fetch_batch(references) = references.map { |reference| fetch_reference(reference) }

        def fetch_passage(reference, position) = references.fetch_passage(reference, position)

        def search(terms, limit: 20) = @maintenance.search(terms, limit:)

        def search_current(terms, limit: 20) = @maintenance.search_current(terms, limit:)

        # Mutates only derived retrieval rows; this operation has no safe counterpart.
        def backfill = @maintenance.backfill
        # Rebuilds only derived retrieval rows from immutable evidence.
        def repair = @maintenance.repair

        attr_reader :references

        private

        def read_documents(intent_id)
          rows = if intent_id
            knowledge.rows("SELECT * FROM documents WHERE intent_id = :intent_id AND origin_id = :origin", intent_id:, origin: origin_id)
          else
            knowledge.rows("SELECT * FROM documents WHERE origin_id = :origin", origin: origin_id)
          end
          rows.map { |row| Graph::Knowledge::Document.from_h(row) }
        end

        def document(intent_id, path)
          knowledge.row(DOCUMENT_SQL, intent_id:, path:, origin: origin_id).then { |row| row && Graph::Knowledge::Document.from_h(row) }
        end

        def origin_id = @origin.id
        def knowledge = @databases.fetch(:knowledge)
      end
    end
  end
end
