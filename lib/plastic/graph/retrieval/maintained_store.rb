# frozen_string_literal: true

require_relative "../origin"
require_relative "../retrieval_graph"
require_relative "../schema"
require_relative "reference_backfill"

module Plastic
  module Graph
    module Retrieval
      # A store a read may open: every store database exists and the knowledge
      # graph carries the retrieval backfill marker of this installation.
      class MaintainedStore
        def initialize(plastic_home, slug)
          @plastic_home = plastic_home
          @slug = slug
        end

        def verify
          return if files? && ReferenceBackfill.complete?(path(Schema.file(:knowledge)), Origin.new(plastic_home).id)

          raise RetrievalGraph::MaintenanceRequired.new("retrieval maintenance is required before source #{slug} can be read", slug:)
        end

        private

        attr_reader :plastic_home, :slug

        def files? = Schema.store.all? { |key| File.file?(path(Schema.file(key))) }

        def path(file) = File.join(plastic_home, "stores", slug, file)
      end
    end
  end
end
