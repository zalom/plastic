# frozen_string_literal: true

require_relative "../../../graph"
require_relative "../maintained_store"

module Plastic
  module Graph
    module Retrieval
      module Context
        # Opens a selected store only after its graph files and retrieval migration are ready.
        class Source
          def initialize(plastic_home)
            @plastic_home = plastic_home
          end

          def retrieval(reference)
            slug = reference[/\Aplastic:\/\/([^\/]+)/, 1]
            MaintainedStore.new(plastic_home, slug).verify
            Graph.open(home: plastic_home, store: slug).retrieval
          end

          private

          attr_reader :plastic_home
        end
      end
    end
  end
end
