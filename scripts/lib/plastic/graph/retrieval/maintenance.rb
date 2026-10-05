# frozen_string_literal: true

require_relative "evidence/integrity"
require_relative "reference_backfill"
require_relative "search"

module Plastic
  module Graph
    module Retrieval
      # Maintains and searches derived retrieval evidence for one origin.
      class Maintenance
        def initialize(databases, origin)
          @databases = databases
          @origin = origin
          @searcher = Search.new(knowledge, origin:)
        end

        def ready_documents
          backfill
          yield
        end

        def search(terms, limit:)
          backfill
          @searcher.call(terms, limit:)
        end

        def search_current(terms, limit:)
          require_backfilled
          @searcher.call(terms, limit:)
        end

        # Mutates only derived retrieval rows; this Stage 6 operation has no safe counterpart.
        def backfill = ReferenceBackfill.new(@databases, origin_id).call
        # Rebuilds only derived retrieval rows from immutable evidence.
        def repair = Evidence::Integrity.new(knowledge, origin_id).repair

        private

        def require_backfilled
          return if ReferenceBackfill.complete?(knowledge.path, origin_id)

          raise RetrievalGraph::MaintenanceRequired, "retrieval migration is required before a selected source can be read"
        end

        def origin_id = @origin.id
        def knowledge = @databases.fetch(:knowledge)
      end
    end
  end
end
