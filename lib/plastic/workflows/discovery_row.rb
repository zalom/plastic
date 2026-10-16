# frozen_string_literal: true

require_relative "passage_rows"
require_relative "../graph/retrieval/search/excerpt"

module Plastic
  module Workflows
    # The discovery row a call prints: the recorded discovery with each
    # candidate shown as the passage that matched the query.
    class DiscoveryRow
      def initialize(context)
        @context = context
      end

      def to_h
        discovery = @context.discovery.transform_keys(&:to_s)
        discovery.merge("candidates" => passages.call(discovery.fetch("candidates")))
      end

      private

      def passages
        excerpt = Graph::Retrieval::Search::Excerpt.new(@context.terms)
        PassageRows.new(passage_of: ->(row) { excerpt.call(row.fetch("body")) })
      end
    end
  end
end
