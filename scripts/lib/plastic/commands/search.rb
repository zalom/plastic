# frozen_string_literal: true

require_relative "../cli/command"
require_relative "../graph/retrieval_source"
require_relative "search_excerpt"
require_relative "search_results"
require_relative "search_scope"

module Plastic
  module Commands
    # Searches literal indexed passages in the selected local stores.
    class Search < CLI::Command
      argument :terms, label: "TERMS", text: "literal search terms", rest: true
      option :source_projects, switch: "--source-project SLUG", text: "a source store", repeatable: true
      option :limit, switch: "--limit N", text: "maximum passages", default: 20
      reads :knowledge

      def call
        write_results
      rescue Graph::RetrievalGraph::InvalidSearch => error
        raise_failure(CLI::Command::Usage, error)
      rescue Graph::RetrievalGraph::MaintenanceRequired => error
        raise_failure(CLI::Command::Failure, error)
      end

      private

      def sources = SearchScope.new(scope, parsed, environment).sources

      def results = SearchResults.new(scope, terms, excerpt: SearchExcerpt.new(terms))

      def terms = parsed.fetch(:terms)

      def write_results = SearchOutput.new(output, results.call(sources, search_limit)).write

      def raise_failure(error_class, error) = raise error_class, error.message

      def search_limit
        limit = Integer(parsed.fetch(:limit))
        return limit if limit.between?(1, Graph::RetrievalGraph::SEARCH_LIMIT)

        raise Graph::RetrievalGraph::InvalidSearch, "search limit must be between 1 and #{Graph::RetrievalGraph::SEARCH_LIMIT}"
      rescue ArgumentError, TypeError
        raise Graph::RetrievalGraph::InvalidSearch, "search limit must be an integer"
      end
    end

    # Writes the command envelope for successful search results.
    class SearchOutput
      def initialize(output, rows)
        @output = output
        @rows = rows
      end

      def write
        output.row("results", rows)
        output.next_step("none", because: "the indexed passages were read")
      end

      private

      attr_reader :output, :rows
    end
  end
end
