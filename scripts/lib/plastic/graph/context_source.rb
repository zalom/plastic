# frozen_string_literal: true

require_relative "../graph"
require_relative "origin"
require_relative "reference_backfill"
require_relative "retrieval_graph"
require_relative "schema"

module Plastic
  module Graph
    # Opens a selected store only after its graph files and retrieval migration are ready.
    class ContextSource
      def initialize(plastic_home)
        @plastic_home = plastic_home
      end

      def retrieval(reference)
        slug = reference[/\Aplastic:\/\/([^\/]+)/, 1]
        verify_store_files(slug)
        verify_backfill(slug)
        Graph.open(home: plastic_home, store: slug).retrieval
      end

      private

      attr_reader :plastic_home

      def verify_store_files(slug)
        store = File.join(plastic_home, "stores", slug)
        missing = Schema.store.map { |key| Schema.file(key) }.reject { |file| File.file?(File.join(store, file)) }
        raise RetrievalGraph::MaintenanceRequired, message(slug) if missing.any?
      end

      def verify_backfill(slug)
        knowledge = File.join(plastic_home, "stores", slug, "knowledge_graph.db")
        complete = ReferenceBackfill.complete?(knowledge, Origin.new(plastic_home).id)
        raise RetrievalGraph::MaintenanceRequired, message(slug) unless complete
      end

      def message(slug) = "retrieval maintenance is required before source #{slug} can be read"
    end
  end
end
