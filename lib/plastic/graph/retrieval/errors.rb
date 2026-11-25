# frozen_string_literal: true

module Plastic
  module Graph
    # Provides ordinary retrieval reads from graph records.
    class RetrievalGraph
      # Signals that a caller must build the derived retrieval rows first.
      class MaintenanceRequired < StandardError
        attr_reader :slug

        def initialize(message = nil, slug: nil)
          super(message)
          @slug = slug
        end
      end

      # Signals an invalid or unavailable document or passage reference.
      class MissingReference < StandardError; end
      # Signals an FTS query that SQLite rejected.
      class InvalidSearch < StandardError; end
    end
  end
end
