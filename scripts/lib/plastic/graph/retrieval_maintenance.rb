# frozen_string_literal: true

require_relative "evidence_integrity"
require_relative "reference_backfill"
require_relative "retrieval_search"

module Plastic
  module Graph
    # Maintains and searches derived retrieval evidence for one origin.
    class RetrievalMaintenance
      def initialize(databases, origin)
        @databases = databases
        @origin = origin
        @searcher = RetrievalSearch.new(knowledge, origin:)
      end

      def ready_documents
        ensure_backfill!
        yield
      end

      def search(terms, limit:, migrate:)
        ensure_backfill!(migrate)
        @searcher.call(terms, limit:)
      end

      def backfill! = ReferenceBackfill.new(@databases, origin_id).call
      def repair! = EvidenceIntegrity.new(knowledge, origin_id).repair!

      private

      def ensure_backfill!(migrate = true)
        return backfill! if migrate
        return if ReferenceBackfill.complete?(knowledge.path, origin_id)

        raise RetrievalGraph::MaintenanceRequired, "retrieval migration is required before a selected source can be read"
      end

      def origin_id = @origin.id
      def knowledge = @databases.fetch(:knowledge)
    end
  end
end
