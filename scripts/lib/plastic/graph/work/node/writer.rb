# frozen_string_literal: true

require_relative "../node"
require_relative "../../sql"
require_relative "../../next_id"

module Plastic
  module Graph
    module Work
      class Node
        # Writes one intent's nodes: adds one, and moves one through its states.
        # Each move is a guarded UPDATE, so two moves of the same node cannot
        # both win; the one that finds no row back learns the state from a
        # fresh read. Every move but claim takes the same shape, so it
        # configures itself into MOVES instead of repeating that shape.
        class Writer
          RETRY_CAP = 3

          MOVES = {
            remove_node: { to: "removed", from: %w[open] },
            release_node: { to: "open", from: %w[claimed failed] },
            done_node: { to: "done", from: %w[claimed] },
            repair_done_node: { to: "done", from: %w[done] },
            fail_node: { to: "failed", from: %w[claimed] },
            ask_node: { to: "needs_info", from: %w[claimed] },
            impede_node: { to: "impeded", from: %w[claimed] },
            resolve_node: { to: "open", from: %w[needs_info impeded], resets_retries: true }
          }.freeze

          CLAIM_MOVE = { to: "claimed", from: %w[open] }.freeze
          CAP_MOVE = { to: "needs_info", from: %w[open] }.freeze

          def initialize(databases, retrieval)
            @databases = databases
            @retrieval = retrieval
          end

          def add_node(intent_id:, **fields)
            id = next_id(intent_id)
            row = { intent_id:, id:, kind: "work", state: "open", retries: 0, updated_at: Plastic.now }.merge(fields)
            @databases.fetch(:work).transaction { |batch| batch.put(:nodes, row, statement: :insert) }
            @retrieval.node(intent_id, id)
          end

          MOVES.each do |name, move|
            define_method(name) do |intent_id:, id:, **fields|
              set = move[:resets_retries] ? fields.merge(retries: 0) : fields
              moved({ intent_id:, id: }, move, set:)
            end
          end

          # Returns [:claimed, node], [:capped, node] or [:refused, node].
          def claim_node(intent_id:, id:, by:)
            current = @retrieval.node(intent_id, id)
            return [:refused, nil] unless current
            return [:blocked, current] if current.waiting?(@retrieval.ready_nodes(intent_id))
            return capped(intent_id:, id:) if current.state == "open" && current.retries >= RETRY_CAP

            claimed({ intent_id:, id: }, by:)
          end

          private

          def claimed(key, by:)
            node = moved(key, CLAIM_MOVE, set: { by:, retries: SQL::Raw.new("retries + 1") })
            node ? [:claimed, node] : [:refused, fetched(key)]
          end

          def fetched(key) = @retrieval.node(*key.values_at(:intent_id, :id))

          def capped(key)
            node = moved(key, CAP_MOVE, set: { question: "claimed 3 times; the owner decides" })
            [:capped, node]
          end

          def moved(key, move, set: {})
            rows = @databases.fetch(:work).transaction do |batch|
              batch.write(:nodes, SQL.move(to: move.fetch(:to), from: move.fetch(:from), set:), **key, origin: @retrieval.origin_id)
            end
            rows.any? ? fetched(key) : nil
          end

          def next_id(intent_id) = NextId.after(@retrieval.nodes(intent_id), prefix: "n")
        end
      end
    end
  end
end
