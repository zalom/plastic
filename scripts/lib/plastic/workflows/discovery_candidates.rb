# frozen_string_literal: true

module Plastic
  module Workflows
    # The ranked candidate rows one store contributes to a discovery manifest.
    class DiscoveryCandidates
      def initialize(slug, retrieval)
        @slug = slug
        @retrieval = retrieval
      end

      def rows(terms)
        @retrieval.search(terms, migrate: false).each_with_index.map { |row, index| candidate(row, index) }
      end

      private

      def candidate(row, index)
        reference = @retrieval.search_reference(row).transform_keys(&:to_s)
        row.merge(reference).merge("store" => @slug, "local_rank" => index + 1,
          "rrf_score" => 1.0 / (61 + index), "archived" => @retrieval.archived?(row.fetch("intent_id")))
      end
    end
  end
end
