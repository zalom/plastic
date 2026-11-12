# frozen_string_literal: true

require_relative "../../maintained_store"
require_relative "../../source"

module Plastic
  module Graph
    module Retrieval
      class Search
        class Results
          # Opens a selected store only after confirming retrieval data is available.
          class Store
            def initialize(plastic_home, slug)
              @plastic_home = plastic_home
              @slug = slug
            end

            def retrieval
              MaintainedStore.new(plastic_home, slug).verify
              Graph.open_retrieval(home: plastic_home, store: slug)
            end

            private

            attr_reader :plastic_home, :slug
          end
        end
      end
    end
  end
end
