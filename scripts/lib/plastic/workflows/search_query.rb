# frozen_string_literal: true

require_relative "../cli/command/usage"
require_relative "../graph/retrieval_graph"
require_relative "../graph/retrieval/search/excerpt"
require_relative "../graph/retrieval/search/results"
require_relative "search_scope"

module Plastic
  module Workflows
    # Runs a literal search over the selected stores and returns the fused passages.
    class SearchQuery
      def initialize(context)
        @context = context
      end

      def rows
        results.call(SearchScope.new(context).sources, limit)
      rescue Graph::RetrievalGraph::InvalidSearch => error
        raise CLI::Command::Usage, error.message
      end

      private

      attr_reader :context

      def results
        terms = context.terms
        Graph::Retrieval::Search::Results.new(context.scope.plastic_home, terms, excerpt: Graph::Retrieval::Search::Excerpt.new(terms))
      end

      def limit
        number = Integer(context.limit)
        return number if number.between?(1, Graph::RetrievalGraph::SEARCH_LIMIT)

        raise Graph::RetrievalGraph::InvalidSearch, "search limit must be between 1 and #{Graph::RetrievalGraph::SEARCH_LIMIT}"
      rescue ArgumentError, TypeError
        raise Graph::RetrievalGraph::InvalidSearch, "search limit must be an integer"
      end
    end
  end
end
