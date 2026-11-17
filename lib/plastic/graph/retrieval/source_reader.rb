# frozen_string_literal: true

require_relative "../source"

module Plastic
  module Graph
    module Retrieval
      # Reads the rows of one origin from the graph sources.
      class SourceReader
        def initialize(databases, origin_id)
          @databases = databases
          @origin_id = origin_id
        end

        private

        attr_reader :databases, :origin_id

        def read(name, intent_id = nil) = SOURCES.fetch(name).read(databases, origin: origin_id, intent_id:)
      end
    end
  end
end
