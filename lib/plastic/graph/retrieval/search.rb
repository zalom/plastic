# frozen_string_literal: true

require_relative "errors"
require_relative "search/query"

module Plastic
  module Graph
    module Retrieval
      # Searches indexed passages for the words of a question, ranked by BM25 (see Search::Query). A hit whose hash is not the current head of its document is dropped.
      class Search
        SEARCH_LIMIT = 100
        SEARCH_SQL = "SELECT intent_id, path, body, sha256, position, bm25(document_fts) AS score " \
                     "FROM document_fts WHERE document_fts MATCH :query AND origin_id = :origin " \
                     "ORDER BY score, intent_id, path, position LIMIT :limit"
        HEADS_SQL = "SELECT intent_id, path, sha256 FROM document_heads WHERE origin_id = :origin"
        MISSING = "the search index is missing; run plastic doctor to rebuild it"

        def initialize(store, origin:)
          @store = store
          @origin = origin
        end

        def call(terms, limit: 20)
          require_valid(terms, limit)
          raise RetrievalGraph::MaintenanceRequired, MISSING unless store.retrieval_present?

          current(store.rows(SEARCH_SQL, query: self.class.fts_query(terms), origin: origin.id, limit:))
        end

        def self.fts_query(terms) = Query.new(terms).to_s

        private

        attr_reader :store, :origin

        def current(hits)
          return hits if hits.empty?

          heads = store.rows(HEADS_SQL, origin: origin.id).to_set { |row| row.values_at("intent_id", "path", "sha256") }
          hits.select { |hit| heads.include?(hit.values_at("intent_id", "path", "sha256")) }
        end

        def require_valid(terms, limit)
          raise RetrievalGraph::InvalidSearch, "search terms are required" if terms.to_s.scan(/\p{Alnum}+/).empty?
          raise RetrievalGraph::InvalidSearch, "search limit must be between 1 and #{SEARCH_LIMIT}" unless limit.is_a?(Integer) && limit.between?(1, SEARCH_LIMIT)
        end
      end
    end
  end
end
