# frozen_string_literal: true

require_relative "../errors"
require_relative "../scope"
require_relative "../graph"
require_relative "../graph/retrieval/address"
require_relative "../graph/retrieval/maintained_store"
require_relative "../graph/retrieval_graph"
require_relative "../graph/retrieval_source"
require_relative "document_reference"

module Plastic
  module Workflows
    # Fetches documents by qualified reference from the store each one names.
    class DocumentLookup
      FAILURES = [Graph::RetrievalGraph::MissingReference, Graph::RetrievalGraph::MaintenanceRequired, Scope::UnknownProject].freeze

      def initialize(context)
        @context = context
      end

      def fetch(reference) = retrieval_for(reference).fetch_reference(reference)

      # A pinned reference whose text has changed since reads the current text, and the answer names the old reference
      # as changed_since, the way context freshness reports a stale reference and goes on.
      def selected(reference, passage)
        retrieval = retrieval_for(reference)
        current = reference.sub(Graph::Retrieval::Address::PIN, "")
        document = passage ? retrieval.fetch_passage(current, position(passage)) : retrieval.fetch_reference(current)
        (current == reference || document.fetch(:uri) == reference) ? document : document.merge(changed_since: reference)
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

        raise Usage, "passage must be a positive integer"
      end

      def require_source(slug)
        return if context.scope.known_slugs.include?(slug)

        raise Scope::UnknownProject, "no project named #{slug.inspect}"
      end

      def maintained_retrieval(slug)
        home = context.scope.plastic_home
        Graph::Retrieval::MaintainedStore.new(home, slug).verify
        Graph.open_retrieval(home:, store: slug)
      end
    end
  end
end
