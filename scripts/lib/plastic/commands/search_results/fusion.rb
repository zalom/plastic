# frozen_string_literal: true

module Plastic
  module Commands
    # Sorts passages by reciprocal-rank score, then by stable reference.
    class SearchFusion
      def initialize(rows, limit)
        @rows = rows
        @limit = limit
      end

      def call = rows.sort_by { |row| [-row.fetch("rrf_score"), row.fetch("uri")] }.take(limit)

      private

      attr_reader :limit, :rows
    end
  end
end
