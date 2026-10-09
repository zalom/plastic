# frozen_string_literal: true

require_relative "../cli/command/usage"
require_relative "../cli/scope"
require_relative "../graph"
require_relative "../graph/retrieval_graph"
require_relative "../graph/retrieval/source"
require_relative "document_reference"

module Plastic
  module Workflows
    # Fetches documents by qualified reference from the store each one names.
    class DocumentLookup
      FAILURES = [Graph::RetrievalGraph::MissingReference, Graph::RetrievalGraph::MaintenanceRequired, CLI::Scope::UnknownProject].freeze

      def initialize(context)
        @context = context
      end

      def fetch(reference) = retrieval_for(reference).fetch_reference(reference)

      def selected(reference, passage)
        return fetch(reference) unless passage

        retrieval_for(reference).fetch_passage(reference, position(passage))
      end

      private

      attr_reader :context

      def retrieval_for(reference)
        slug = DocumentReference.new(reference).source_slug
        require_source(slug)
        maintained_retrieval(slug)
      end

      def position(passage)
        number = Integer(passage, exception: false).to_i
        return number if number.positive?

        raise CLI::Command::Usage, "passage must be a positive integer"
      end

      def require_source(slug)
        return if context.scope.known_slugs.include?(slug)

        raise CLI::Scope::UnknownProject, "no project named #{slug.inspect}"
      end

      def maintained_retrieval(slug)
        home = context.scope.plastic_home
        raise Graph::RetrievalGraph::MaintenanceRequired, "retrieval maintenance is required before source #{slug} can be read" unless File.file?(File.join(home, "stores", slug, "knowledge_graph.db"))

        Graph.open_retrieval(home:, store: slug).tap(&:backfill)
      end
    end
  end
end
