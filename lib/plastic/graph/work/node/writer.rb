# frozen_string_literal: true

require_relative "../node"
require_relative "../../sql"
require_relative "../../next_id"
require_relative "claim"

module Plastic
  module Graph
    module Work
      class Node
        # Writes one intent's nodes: adds one, and moves one through its states.
        # Each move is a guarded UPDATE, so two moves of the same node cannot
        # both win; the one that finds no row back learns the state from a
        # fresh read. A move names the session that holds the node, and a node
        # another session holds does not move. Every move but claim takes the
        # same shape, so it configures itself into MOVES instead of repeating
        # that shape.
        class Writer
          RETRY_CAP = 3
          RELEASED = { claimed_by: nil, claimed_at: nil, seen_at: nil }.freeze

          MOVES = {
            remove_node: { to: "removed", from: %w[open] },
            release_node: { to: "open", from: %w[claimed failed], result: "released" },
            done_node: { to: "done", from: %w[claimed] },
            fail_node: { to: "failed", from: %w[claimed] },
            ask_node: { to: "needs_info", from: %w[claimed] },
            impede_node: { to: "impeded", from: %w[claimed] },
            resolve_node: { to: "open", from: %w[needs_info impeded], stamp: :answered_at }
          }.freeze

          CAP_MOVE = { to: "needs_info", from: %w[open] }.freeze

          CLOSE_RUN_SQL = <<~SQL
            UPDATE runs SET ended_at = :ended_at, result = :result
            WHERE intent_id = :intent_id AND node_id = :id AND origin_id = :origin AND ended_at IS NULL
              AND EXISTS (SELECT 1 FROM nodes WHERE intent_id = :intent_id AND id = :id AND origin_id = :origin
                AND state IN (%<states>s) %<guard>s)
          SQL

          def initialize(databases, retrieval, clock: Time)
            @databases = databases
            @retrieval = retrieval
            @clock = clock
            @claim = Claim.new(databases, retrieval, clock)
          end

          def add_node(intent_id:, **fields)
            id = next_id(intent_id)
            row = { intent_id:, id:, kind: "work", state: "open", updated_at: Plastic.timestamp(@clock.now) }.merge(fields)
            @databases.fetch(:store).transaction { |batch| batch.put(:nodes, row, statement: :insert) }
            @retrieval.node(intent_id, id)
          end

          MOVES.each do |name, move|
            define_method(name) do |intent_id:, id:, by: nil, **fields|
              moved({ intent_id:, id: }, move, holder: by, set: stamped(move, fields))
            end
          end

          # Returns [:claimed, node], [:held, node], [:capped, node], [:blocked, node] or [:refused, node].
          def claim_node(intent_id:, id:, by:, agent: "")
            current = @retrieval.node(intent_id, id)
            return [:refused, nil] unless current
            return [:blocked, current] if current.waiting?(@retrieval.ready_nodes(intent_id))
            return capped(intent_id:, id:) if current.capped?(@retrieval.structure.runs(intent_id), RETRY_CAP)

            @claim.call(current, by:, agent:)
          end

          def renew_claims(session)
            now = Plastic.timestamp(@clock.now)
            @databases.fetch(:store).transaction do |batch|
              batch.add("UPDATE nodes SET seen_at = :now WHERE claimed_by = :session AND state = 'claimed' AND origin_id = :origin",
                now:, session:, origin: @retrieval.origin_id)
            end
          end

          private

          def stamped(move, fields)
            stamp = move[:stamp]
            stamp ? fields.merge(stamp => Plastic.timestamp(@clock.now)) : fields
          end

          def fetched(key) = @retrieval.node(*key.values_at(:intent_id, :id))

          def capped(key)
            node = moved(key, CAP_MOVE, set: { question: "claimed 3 times; the owner decides" })
            [:capped, node]
          end

          def moved(key, move, set: {}, holder: nil)
            now = @clock.now
            to, from = move.values_at(:to, :from)
            bound = SQL.move(to:, from:, set: RELEASED.merge(set), holder:, now:)
            rows = @databases.fetch(:store).transaction do |batch|
              close_run(batch, key, from, holder, { ended_at: Plastic.timestamp(now), result: move.fetch(:result, to) })
              batch.write(:nodes, bound.sql, **bound.values, **key, origin: @retrieval.origin_id)
            end
            rows.any? ? fetched(key) : nil
          end

          def close_run(batch, key, from, holder, ending)
            states = SQL.list(from, "r")
            sql = format(CLOSE_RUN_SQL, states: states.sql, guard: holder ? SQL::HOLDER_GUARD : "")
            batch.add(sql, **states.values, **key, **(holder ? { holder: } : {}), **ending, origin: @retrieval.origin_id)
          end

          def next_id(intent_id) = NextId.after(@retrieval.structure.nodes(intent_id), prefix: "n")
        end
      end
    end
  end
end
