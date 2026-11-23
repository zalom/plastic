# frozen_string_literal: true

module Plastic
  module Graph
    module Work
      class Node
        # The session ended: each node it claims is open again, and its run ends as released.
        class Release
          RUNS_SQL = <<~SQL
            UPDATE runs SET ended_at = :now, result = 'released'
            WHERE origin_id = :origin AND ended_at IS NULL
              AND EXISTS (SELECT 1 FROM nodes WHERE nodes.intent_id = runs.intent_id AND nodes.id = runs.node_id
                AND nodes.origin_id = :origin AND nodes.state = 'claimed' AND nodes.claimed_by = :session)
          SQL

          NODES_SQL = <<~SQL
            UPDATE nodes SET state = 'open', claimed_by = NULL, claimed_at = NULL, seen_at = NULL, updated_at = :now
            WHERE origin_id = :origin AND state = 'claimed' AND claimed_by = :session
          SQL

          def initialize(databases, retrieval, clock: Time)
            @databases = databases
            @retrieval = retrieval
            @clock = clock
          end

          def call(session)
            bind = { now: Plastic.timestamp(@clock.now), session:, origin: @retrieval.origin_id }
            @databases.fetch(:store).transaction do |batch|
              batch.add(RUNS_SQL, **bind)
              batch.add(NODES_SQL, **bind)
            end
          end
        end
      end
    end
  end
end
