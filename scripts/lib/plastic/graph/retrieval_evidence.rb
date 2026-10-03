# frozen_string_literal: true

require_relative "retrieval_reference"
require_relative "retrieval_maintenance"

module Plastic
  module Graph
    # Reads, repairs, and searches the retrieval evidence in one store.
    class RetrievalEvidence
      DOCUMENT_SQL = "SELECT * FROM documents WHERE intent_id = :intent_id AND path = :path AND origin_id = :origin"

      def initialize(databases, store:, origin:)
        @databases = databases
        @origin = origin
        @references = RetrievalReference.new(databases, store:, origin:)
        @maintenance = RetrievalMaintenance.new(databases, origin)
      end

      def documents(intent_id = nil) = @maintenance.ready_documents { read_documents(intent_id) }

      def fetch(intent_id, path) = @maintenance.ready_documents { document(intent_id, path) }

      def reference(intent_id, path) = references.reference(intent_id, path)

      def fetch_reference(reference) = references.fetch(reference)

      def fetch_batch(references) = references.map { |reference| fetch_reference(reference) }

      def fetch_passage(reference, position) = references.fetch_passage(reference, position)

      def exact_lookup_plans(intent_id, path)
        [work.rows("EXPLAIN QUERY PLAN SELECT * FROM intents WHERE intent_id = :intent_id AND origin_id = :origin", intent_id:, origin: origin_id),
          knowledge.rows("EXPLAIN QUERY PLAN #{DOCUMENT_SQL}", intent_id:, path:, origin: origin_id)]
      end

      def search(terms, limit: 20, migrate: true)
        @maintenance.search(terms, limit:, migrate:)
      end

      def search_reference(row) = references.qualified_reference(row.fetch("intent_id"), row.fetch("path"), row.fetch("sha256"))

      def backfill! = @maintenance.backfill!
      def repair! = @maintenance.repair!

      private

      def read_documents(intent_id)
        rows = if intent_id
          knowledge.rows("SELECT * FROM documents WHERE intent_id = :intent_id AND origin_id = :origin", intent_id:, origin: origin_id)
        else
          knowledge.rows("SELECT * FROM documents WHERE origin_id = :origin", origin: origin_id)
        end
        rows.map { |row| Document.from_h(row) }
      end

      def document(intent_id, path)
        knowledge.row(DOCUMENT_SQL, intent_id:, path:, origin: origin_id).then { |row| row && Document.from_h(row) }
      end

      def origin_id = @origin.id
      def knowledge = @databases.fetch(:knowledge)
      def work = @databases.fetch(:work)
      attr_reader :references
    end
  end
end
