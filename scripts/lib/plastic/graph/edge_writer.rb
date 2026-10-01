# frozen_string_literal: true

require_relative "sql"

module Plastic
  module Graph
    # Writes one intent's edges: one guarded INSERT that refuses a self
    # edge, an edge touching a missing or removed node, or an edge that
    # would close a loop back to its own start.
    class EdgeWriter
      ADD_SQL = <<~SQL
        INSERT INTO edges (intent_id, "from", "to", kind, origin_id)
        SELECT :intent_id, :from, :to, :kind, :origin
        WHERE :from != :to
          AND EXISTS (SELECT 1 FROM nodes WHERE intent_id = :intent_id AND id = :from
                        AND origin_id = :origin AND state != 'removed')
          AND EXISTS (SELECT 1 FROM nodes WHERE intent_id = :intent_id AND id = :to
                        AND origin_id = :origin AND state != 'removed')
          AND NOT EXISTS (
            WITH RECURSIVE reach(id) AS (
              SELECT "to" FROM edges WHERE intent_id = :intent_id AND origin_id = :origin AND "from" = :to
              UNION
              SELECT edges."to" FROM edges, reach
              WHERE edges.intent_id = :intent_id AND edges.origin_id = :origin AND edges."from" = reach.id
            )
            SELECT 1 FROM reach WHERE id = :from
          )
        RETURNING "from"
      SQL

      def initialize(databases, retrieval)
        @databases = databases
        @retrieval = retrieval
      end

      def add_edge(intent_id:, from:, to:)
        rows = @databases.fetch(:work).transaction do |batch|
          batch.write(:edges, ADD_SQL, intent_id:, from:, to:, kind: "needs", origin: @retrieval.origin_id)
        end
        rows.any?
      end

      def remove_edge(intent_id:, from:, to:)
        database = @databases.fetch(:work)
        written = database.written
        before = written["edges"]
        database.transaction { |batch| batch.remove(:edges, intent_id:, from:, to:, origin_id: @retrieval.origin_id) }
        written["edges"] > before
      end
    end
  end
end
