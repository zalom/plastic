# frozen_string_literal: true

require_relative "search_results/fusion"
require_relative "search_results/result"
require_relative "search_results/store"

module Plastic
  module Commands
    # Reads per-store matches and merges them with reciprocal-rank fusion.
    class SearchResults
      RRF_OFFSET = 60

      def initialize(scope, terms, excerpt:)
        @scope = scope
        @terms = terms
        @excerpt = excerpt
        @rrf_offset = RRF_OFFSET
      end

      def call(sources, limit)
        SearchFusion.new(sources.flat_map { |slug| store_rows(slug, limit) }, limit).call
      end

      private

      attr_reader :excerpt, :rrf_offset, :scope, :terms

      def store_rows(slug, limit)
        retrieval = SearchStore.new(scope.plastic_home, slug).retrieval
        retrieval.search(terms, limit:, migrate: false).each_with_index.map do |row, index|
          match = SearchMatch.new(retrieval, slug, row, index + 1, rrf_offset)
          SearchResult.new(match, excerpt:).to_h
        end
      end
    end
  end
end
