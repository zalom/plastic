# frozen_string_literal: true

require_relative "edge_findings"

module Plastic
  module Graph
    module Knowledge
      class Findings
        # The schema files of an intent that name no live node: the node was removed, or the file has the wrong name.
        class SchemaFindings
          def initialize(intent_id, live_ids, schemas)
            @intent_id = intent_id
            @live_ids = live_ids.to_set
            @schemas = schemas
          end

          def all
            return [] unless @schemas

            @schemas.ids.reject { |id| @live_ids.include?(id) }.map do |id|
              Finding.new("schema #{@schemas.relative(id)} names no live node; rename it to a live node id or delete it", nil)
            end
          end
        end
      end
    end
  end
end
