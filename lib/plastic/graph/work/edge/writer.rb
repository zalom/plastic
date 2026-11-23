# frozen_string_literal: true

require_relative "../../rows/edge"
require_relative "../../sql"
require_relative "../../edge_walk"

module Plastic
  module Graph
    module Work
      class Edge
        # Writes one intent's edges. An edge is added inside one immediate transaction that first reads the intent's
        # nodes and edges and refuses a self edge, a missing or removed node, a duplicate edge and an edge that would
        # close a loop, so two sessions cannot close a loop between them. An EdgeWalk finds the loop, not a query.
        class Writer
          ADD_SQL = <<~SQL
            INSERT INTO edges (intent_id, "from", "to", kind, origin_id)
            VALUES (:intent_id, :from, :to, :kind, :origin)
            RETURNING "from"
          SQL

          REMOVE_SQL = <<~SQL
            DELETE FROM edges WHERE intent_id = :intent_id AND "from" = :from AND "to" = :to AND origin_id = :origin AND kind = 'needs'
            RETURNING "from"
          SQL

          NODE_SQL = "SELECT state FROM nodes WHERE intent_id = :intent_id AND id = :id AND origin_id = :origin"

          EDGES_SQL = <<~SQL
            SELECT "from", "to" FROM edges WHERE intent_id = :intent_id AND origin_id = :origin AND kind = 'needs'
          SQL

          def initialize(databases, retrieval)
            @databases = databases
            @retrieval = retrieval
          end

          # Returns one of three results:
          #   [true, nil, nil]         the edge is written;
          #   [false, message, :missing]  an end of the edge is not a node of the intent, which the command exits 1 on;
          #   [false, message, :refused]  the edge is a self edge, a duplicate, a loop, or touches a removed node, which the command exits 3 on.
          # The kind comes from the reason itself, never from reading the message.
          def add_edge(intent_id:, from:, to:)
            store.atomically do
              problem, kind = refusal(intent_id, from, to)
              problem ? [false, problem, kind] : [moved(ADD_SQL, intent_id:, from:, to:), nil, nil]
            end
          end

          def remove_edge(intent_id:, from:, to:)
            moved(REMOVE_SQL, intent_id:, from:, to:)
          end

          private

          def store = @databases.fetch(:store)

          def moved(sql, **edge)
            rows = store.transaction do |batch|
              batch.write(:edges, sql, **edge, kind: "needs", origin: @retrieval.origin_id)
            end
            rows.any?
          end

          def refusal(intent_id, from, to)
            kind, reason = self_reason(from, to) || node_reason(intent_id, from, to) || edge_reason(intent_id, from, to)
            return unless reason

            lead = kind == :missing ? "is missing a node" : "is refused"
            ["edge #{from} to #{to} #{lead}: #{reason}", kind]
          end

          def self_reason(from, to) = ([:refused, "a node cannot need itself"] if from == to)

          def node_reason(intent_id, from, to)
            [from, to].each do |id|
              state = store.row(NODE_SQL, intent_id:, id:, origin: @retrieval.origin_id)&.fetch("state")
              return [:missing, "#{id} is not a node of intent #{intent_id}"] if state.nil?
              return [:refused, "#{id} is removed"] if state == "removed"
            end
            nil
          end

          def edge_reason(intent_id, from, to)
            pairs = store.rows(EDGES_SQL, intent_id:, origin: @retrieval.origin_id).map { |row| [row.fetch("from"), row.fetch("to")] }
            return [:refused, "it is already there"] if pairs.include?([from, to])

            path = EdgeWalk.new(pairs).path(to, from)
            [:refused, "it would loop, #{[from, *path].join(" -> ")}"] if path
          end
        end
      end
    end
  end
end
