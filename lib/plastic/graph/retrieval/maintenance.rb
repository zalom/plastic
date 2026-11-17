# frozen_string_literal: true

require_relative "evidence/integrity"
require_relative "index"
require_relative "search"

module Plastic
  module Graph
    module Retrieval
      # Maintains and searches derived retrieval evidence for one origin.
      class Maintenance
        def initialize(databases, origin)
          @databases = databases
          @origin = origin
          @searcher = Search.new(knowledge, retrieval, origin:)
        end

        def search(terms, limit:) = @searcher.call(terms, limit:)

        # Rebuilds the heads, the passages and the search entries from the immutable evidence.
        def repair = integrity.repair

        # Rebuilds the passages and the search entries of one intent, or of every intent when none is named.
        def reindex(intent_id = nil) = Index.new(knowledge, retrieval, origin_id).rebuild_intent(intent_id)

        # Compares the derived rows with the immutable evidence and changes none.
        def search_index_report = integrity.report

        private

        def integrity = Evidence::Integrity.new(knowledge, retrieval, origin_id)

        def origin_id = @origin.id
        def knowledge = @databases.fetch(:knowledge)
        def retrieval = @databases.fetch(:retrieval)
      end
    end
  end
end
