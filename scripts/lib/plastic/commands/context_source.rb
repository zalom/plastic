# frozen_string_literal: true

module Plastic
  module Commands
    # Opens a selected store only after its graph files and retrieval migration are ready.
    class ContextSource
      def initialize(scope)
        @scope = scope
      end

      def retrieval(reference)
        slug = source(reference)
        verify_store_files(slug)
        verify_backfill(slug)
        Graph.open(home: plastic_home, store: slug).retrieval
      end

      private

      attr_reader :scope

      def source(reference) = reference[/\Aplastic:\/\/([^\/]+)/, 1]

      def plastic_home = scope.plastic_home

      def verify_store_files(slug)
        store = File.join(plastic_home, "stores", slug)
        missing = Graph::Schema.store.map { |key| Graph::Schema.file(key) }.reject { |file| File.file?(File.join(store, file)) }
        raise Graph::RetrievalGraph::MaintenanceRequired, message(slug) if missing.any?
      end

      def verify_backfill(slug)
        knowledge = File.join(plastic_home, "stores", slug, "knowledge_graph.db")
        complete = Graph::ReferenceBackfill.complete?(knowledge, Graph::Origin.new(plastic_home).id)
        raise Graph::RetrievalGraph::MaintenanceRequired, message(slug) unless complete
      end

      def message(slug) = "retrieval maintenance is required before source #{slug} can be read"
    end
  end
end
