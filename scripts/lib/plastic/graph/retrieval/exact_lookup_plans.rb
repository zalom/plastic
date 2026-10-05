# frozen_string_literal: true

require_relative "evidence"

module Plastic
  module Graph
    module Retrieval
      # Explains the query plans of the exact intent and document lookups.
      class ExactLookupPlans
        INTENT_SQL = "SELECT * FROM intents WHERE intent_id = :intent_id AND origin_id = :origin"

        def initialize(databases, origin_id)
          @databases = databases
          @origin_id = origin_id
        end

        def rows(intent_id, path)
          [plan(:work, INTENT_SQL, intent_id:),
            plan(:knowledge, Evidence::DOCUMENT_SQL, intent_id:, path:)]
        end

        private

        def plan(name, sql, **values) = @databases.fetch(name).rows("EXPLAIN QUERY PLAN #{sql}", **values, origin: @origin_id)
      end
    end
  end
end
