# frozen_string_literal: true

module Plastic
  module Graph
    # Searches indexed passages with bounded literal FTS terms.
    class RetrievalSearch
      SEARCH_LIMIT = 100
      SEARCH_SQL = "SELECT intent_id, path, body, sha256, position, bm25(document_fts) AS score " \
                   "FROM document_fts WHERE document_fts MATCH :query AND origin_id = :origin " \
                   "ORDER BY score, intent_id, path, position LIMIT :limit"

      def initialize(database, origin:)
        @database = database
        @origin = origin
      end

      def call(terms, limit: 20)
        require_valid(terms, limit)
        database.rows(SEARCH_SQL, query: self.class.fts_query(terms), origin: origin.id, limit:)
      end

      def self.fts_query(terms) = terms.to_s.scan(/[\p{Alnum}_]+/).map { |term| %("#{term}") }.join(" AND ")

      private

      attr_reader :database, :origin

      def require_valid(terms, limit)
        raise RetrievalGraph::InvalidSearch, "search terms are required" if terms.to_s.scan(/\p{Alnum}+/).empty?
        raise RetrievalGraph::InvalidSearch, "search limit must be between 1 and #{SEARCH_LIMIT}" unless limit.is_a?(Integer) && limit.between?(1, SEARCH_LIMIT)
      end
    end
  end
end
