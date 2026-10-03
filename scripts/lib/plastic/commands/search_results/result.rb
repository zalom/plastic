# frozen_string_literal: true

require "forwardable"

module Plastic
  module Commands
    # Holds local search information before it becomes a federated result.
    SearchMatch = Data.define(:retrieval, :slug, :row, :rank, :rrf_offset)

    # Formats one locally ranked passage for a federated result set.
    class SearchResult
      extend Forwardable

      def initialize(match, excerpt:)
        @match = match
        @excerpt = excerpt
      end

      def to_h
        row.merge(retrieval.search_reference(row).transform_keys(&:to_s))
          .merge(details)
          .merge("body" => excerpt.call(row.fetch("body")))
      end

      private

      attr_reader :excerpt, :match

      def_delegators :match, :rank, :retrieval, :row, :rrf_offset, :slug

      def details
        { "store" => slug, "local_rank" => rank, "rrf_score" => 1.0 / (rrf_offset + rank), "archived" => retrieval.archived?(row.fetch("intent_id")) }
      end
    end
  end
end
