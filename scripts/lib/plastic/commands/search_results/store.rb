# frozen_string_literal: true

module Plastic
  module Commands
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

        raise Graph::RetrievalGraph::MaintenanceRequired, "retrieval maintenance is required before source #{slug} can be read"
      end

      def missing_files
        Graph::Schema.store.map { |key| Graph::Schema.file(key) }.reject { |file| File.file?(File.join(store_root, file)) }
      end

      def store_root = File.join(plastic_home, "stores", slug)
    end
  end
end
