# frozen_string_literal: true

require_relative "../origin"
require_relative "errors"
require_relative "../schema"

module Plastic
  module Graph
    module Retrieval
      # A store a read may open: every store database exists and the retrieval database has been built.
      class MaintainedStore
        def initialize(plastic_home, slug)
          @plastic_home = plastic_home
          @slug = slug
        end

        def verify
          return if files?

          raise RetrievalGraph::MaintenanceRequired.new("retrieval maintenance is required before source #{slug} can be read", slug:)
        end

        def only_derived_missing? = Schema.store.all? { |key| File.file?(path(Schema.file(key))) }

        private

        attr_reader :plastic_home, :slug

        def files? = only_derived_missing? && Schema.derived.all? { |key| File.file?(path(Schema.file(key))) }

        def path(file) = File.join(plastic_home, "stores", slug, file)
      end
    end
  end
end
