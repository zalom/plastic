# frozen_string_literal: true

require_relative "../../maintained_store"

module Plastic
  module Graph
    module Retrieval
      class Search
        class Results
          # Opens a selected store only after confirming retrieval data is available.
          class Store
            def initialize(plastic_home, slug, opener)
              @plastic_home = plastic_home
              @opener = opener
              @slug = slug
            end

            def retrieval
              MaintainedStore.new(plastic_home, slug).verify
              opener.open(home: plastic_home, store: slug)
            end

            private

            attr_reader :opener, :plastic_home, :slug
          end
        end
      end
    end
  end
end
