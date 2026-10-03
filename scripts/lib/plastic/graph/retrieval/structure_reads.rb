# frozen_string_literal: true

module Plastic
  module Graph
    module Retrieval
      # Exposes node, savepoint, edge, and link reads through a retrieval graph.
      module StructureReads
        LINKING_SQL = "SELECT * FROM links WHERE origin_id = :origin AND (to_ref = :id OR to_ref LIKE :prefix)"

        def savepoints(intent_id = nil) = read(:savepoints, intent_id)
        def nodes(intent_id = nil) = read(:nodes, intent_id)
        def edges(intent_id = nil) = read(:edges, intent_id)

        def linking(id)
          @databases.fetch(:knowledge).rows(LINKING_SQL, origin: origin_id, id:, prefix: "#{id}/%").map { |row| Link.from_h(row) }
        end
      end
    end
  end
end
