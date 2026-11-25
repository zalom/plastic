# frozen_string_literal: true

require_relative "../maintained_store"

module Plastic
  module Graph
    module Retrieval
      module Context
        # Opens a selected store, through the opener it is given, only after its graph files and retrieval migration are ready.
        class Source
          def initialize(plastic_home, opener:)
            @plastic_home = plastic_home
            @opener = opener
          end

          def retrieval(reference)
            slug = reference[/\Aplastic:\/\/([^\/]+)/, 1]
            MaintainedStore.new(plastic_home, slug).verify
            opener.call(home: plastic_home, store: slug).retrieval
          end

          private

          attr_reader :plastic_home, :opener
        end
      end
    end
  end
end
