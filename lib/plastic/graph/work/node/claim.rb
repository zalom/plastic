# frozen_string_literal: true

require_relative "../node"
require_relative "../../sql"

module Plastic
  module Graph
    module Work
      class Node
        # Takes a node for a session in one transaction: an open node is
        # claimed, and a claimed node whose holder has not renewed it within
        # the lapse is taken over, which closes the old run as lapsed. Every
        # statement is guarded by the state it read, so two sessions cannot
        # both win.
        class Claim
          LAPSED = <<~SQL.strip
            COALESCE(julianday(COALESCE(NULLIF(seen_at, ''), NULLIF(claimed_at, ''))), 0) < julianday(:cutoff)
          SQL

          LAPSE_RUN_SQL = <<~SQL
            UPDATE runs SET ended_at = :now, result = 'lapsed'
            WHERE intent_id = :intent_id AND node_id = :id AND origin_id = :origin AND ended_at IS NULL
              AND EXISTS (SELECT 1 FROM nodes WHERE intent_id = :intent_id AND id = :id AND origin_id = :origin
                AND state = 'claimed' AND claimed_by IS :holder AND #{LAPSED})
          SQL

          TAKE_SQL = <<~SQL
            UPDATE nodes SET state = 'claimed', claimed_by = :by, claimed_at = :now, seen_at = :now, updated_at = :now
            WHERE intent_id = :intent_id AND id = :id AND origin_id = :origin AND %<guard>s
            RETURNING id
          SQL

          OPEN_RUN_SQL = <<~SQL
            INSERT INTO runs (intent_id, node_id, number, agent, session_id, started_at, origin_id)
            SELECT :intent_id, :id,
              (SELECT COUNT(*) + 1 FROM runs WHERE intent_id = :intent_id AND node_id = :id AND origin_id = :origin),
              :agent, :by, :now, :origin
            WHERE EXISTS (SELECT 1 FROM nodes WHERE intent_id = :intent_id AND id = :id AND origin_id = :origin
              AND state = 'claimed' AND claimed_by IS :by AND claimed_at = :now)
          SQL

          OPEN_GUARD = "state = 'open'"
          TAKE_GUARD = "state = 'claimed' AND claimed_by IS :holder AND #{LAPSED}".freeze

          def initialize(databases, retrieval, clock)
            @databases = databases
            @retrieval = retrieval
            @clock = clock
          end

          # [:claimed, node] when the session now holds it, otherwise [:held, node] while another
          # session's claim stands, or [:refused, node] when the node is in no state to claim.
          def call(node, by:, agent:)
            now = @clock.now
            lapsed = node.lapsed?(now)
            return [contested(node), node] unless node.state == "open" || lapsed

            won = win_claim(node, by:, agent:, now:, lapsed:)
            fresh = @retrieval.node(node.intent_id, node.id)
            [won ? :claimed : contested(fresh), fresh]
          end

          private

          def contested(node) = (node.state == "claimed") ? :held : :refused

          def win_claim(node, by:, agent:, now:, lapsed:)
            key = { intent_id: node.intent_id, id: node.id, origin: @retrieval.origin_id }
            values = { by:, agent:, now: Plastic.now(now), cutoff: Plastic.now(now - Node::LAPSE) }
            values = values.merge(holder: node.claimed_by) if lapsed
            rows = @databases.fetch(:work).transaction do |batch|
              batch.add(LAPSE_RUN_SQL, **key, **values) if lapsed
              batch.write(:nodes, format(TAKE_SQL, guard: lapsed ? TAKE_GUARD : OPEN_GUARD), **key, **values)
              batch.add(OPEN_RUN_SQL, **key, **values)
            end
            rows.any?
          end
        end
      end
    end
  end
end
