# frozen_string_literal: true

require_relative "../../rows/node"
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
            WHERE intent_id = :intent_id AND id = :id AND origin_id = :origin
              AND (state = 'open' OR (state = 'claimed' AND claimed_by IS :holder AND #{LAPSED}))
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

          STEPS = [[nil, LAPSE_RUN_SQL], [:nodes, TAKE_SQL], [nil, OPEN_RUN_SQL]].freeze

          def initialize(databases, retrieval, clock)
            @databases = databases
            @retrieval = retrieval
            @clock = clock
          end

          # [:claimed, node] when the session now holds it, otherwise [:held, node] while another
          # session's claim stands, or [:refused, node] when the node is in no state to claim.
          def call(node, by:, agent:)
            now = @clock.now
            reason = node.rejection_at(now)
            return [reason, node] if reason

            won = write_claim(node, { by:, agent:, now: Plastic.timestamp(now), cutoff: Plastic.timestamp(now - Node::LAPSE) })
            fresh = current(node)
            won ? [:claimed, fresh] : [fresh.claim_rejection, fresh]
          end

          private

          def current(node) = @retrieval.node(*node.claim_key.values_at(:intent_id, :id))

          def write_claim(node, claimant)
            bind = { **node.claim_key, origin: @retrieval.origin_id, **claimant }
            @databases.fetch(:store).transaction { |batch| batch.add_steps(STEPS, **bind) }.any?
          end
        end
      end
    end
  end
end
