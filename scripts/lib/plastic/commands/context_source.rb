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
        ensure_files!(slug)
        ensure_backfill!(slug)
        Graph.open(home: scope.plastic_home, store: slug).retrieval
      end

      private

      attr_reader :scope

      def source(reference) = reference[/\Aplastic:\/\/([^\/]+)/, 1]

      def ensure_files!(slug)
        store = File.join(scope.plastic_home, "stores", slug)
        missing = Graph::Schema::STORE.map { |key| Graph::Schema.file(key) }.reject { |file| File.file?(File.join(store, file)) }
        raise Graph::RetrievalGraph::MaintenanceRequired, message(slug) if missing.any?
      end

      def ensure_backfill!(slug)
        knowledge = File.join(scope.plastic_home, "stores", slug, "knowledge_graph.db")
        complete = Graph::ReferenceBackfill.complete?(knowledge, Graph::Origin.new(scope.plastic_home).id)
        raise Graph::RetrievalGraph::MaintenanceRequired, message(slug) unless complete
      end

      def message(slug) = "retrieval maintenance is required before source #{slug} can be read"
    end
  end
end
