# frozen_string_literal: true

require_relative "../retrieval_graph"
require_relative "../retrieval_source"
require_relative "../schema"

module Plastic
  module Graph
    # Opens a selected store only after confirming retrieval data is available.
    class SearchStore
      def initialize(plastic_home, slug)
        @plastic_home = plastic_home
        @slug = slug
      end

      def retrieval
        ensure_maintained
        Graph.open_retrieval(home: plastic_home, store: slug)
      end

      private

      attr_reader :plastic_home, :slug

      def ensure_maintained
        return if missing_files.empty?

        raise RetrievalGraph::MaintenanceRequired, "retrieval maintenance is required before source #{slug} can be read"
      end

      def missing_files
        Schema.store.map { |key| Schema.file(key) }.reject { |file| File.file?(File.join(store_root, file)) }
      end

      def store_root = File.join(plastic_home, "stores", slug)
    end
  end
end
