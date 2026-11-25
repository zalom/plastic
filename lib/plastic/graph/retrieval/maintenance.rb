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
          @searcher = Search.new(store, origin:)
        end

        def search(terms, limit:) = @searcher.call(terms, limit:)

        # Rebuilds the heads, the passages and the search entries from the current documents.
        def repair = integrity.repair

        # Rebuilds the passages and the search entries of the intents `intent_ids` in one pass, or of every intent when
        # none is named.
        def reindex(intent_ids = nil) = intent_ids ? index.rebuild_intents(intent_ids) : index.rebuild

        # Compares the derived rows with the current documents and changes none.
        def search_index_report = integrity.report

        private

        def index = Index.new(store, origin_id)

        def integrity = Evidence::Integrity.new(store, origin_id)

        def origin_id = @origin.id
        def store = @databases.fetch(:store)
      end
    end
  end
end
