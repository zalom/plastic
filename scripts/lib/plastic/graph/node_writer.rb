# frozen_string_literal: true

require_relative "sql"
require_relative "next_id"

module Plastic
  module Graph
    # Writes one intent's nodes: adds one, and moves one through its states.
    # Each move is a guarded UPDATE, so two moves of the same node cannot
    # both win; the one that finds no row back learns the state from a
    # fresh read. Every move but claim takes the same shape, so it
    # configures itself into MOVES instead of repeating that shape.
    class NodeWriter
      RETRY_CAP = 3

      Ref = Data.define(:intent_id, :id)

      MOVES = {
        remove_node: { to: "removed", from: %w[open] },
        release_node: { to: "open", from: %w[claimed failed] },
        done_node: { to: "done", from: %w[claimed] },
        fail_node: { to: "failed", from: %w[claimed] },
        park_node: { to: "parked", from: %w[claimed] },
        answer_node: { to: "open", from: %w[parked], resets_retries: true }
      }.freeze

      CLAIM_MOVE = { to: "claimed", from: %w[open] }.freeze
      CAP_MOVE = { to: "parked", from: %w[open] }.freeze

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
          moved(Ref.new(intent_id:, id:), move, set:)
        end
      end

      # Returns [:claimed, node], [:capped, node] or [:refused, node].
      def claim_node(intent_id:, id:, by:)
        ref = Ref.new(intent_id:, id:)
        current = @retrieval.node(intent_id, id)
        return [:refused, nil] unless current
        return [:blocked, current] if blocked?(current)
        return capped(ref) if current.state == "open" && current.retries >= RETRY_CAP

        claimed(ref, by:)
      end

      private

      def claimed(ref, by:)
        node = moved(ref, CLAIM_MOVE, set: { by:, retries: SQL::Raw.new("retries + 1") })
        node ? [:claimed, node] : [:refused, refetched(ref)]
      end

      def blocked?(node) = node.state == "open" && @retrieval.ready_nodes(node.intent_id).none? { |ready| ready.id == node.id }

      def refetched(ref) = @retrieval.node(ref.intent_id, ref.id)

      def capped(ref)
        node = moved(ref, CAP_MOVE, set: { question: "claimed 3 times; the owner decides" })
        [:capped, node]
      end

      def moved(ref, move, set: {})
        rows = @databases.fetch(:work).transaction do |batch|
          batch.write(:nodes, SQL.move(to: move.fetch(:to), from: move.fetch(:from), set:),
            intent_id: ref.intent_id, id: ref.id, origin: @retrieval.origin_id)
        end
        rows.any? ? @retrieval.node(ref.intent_id, ref.id) : nil
      end

      def next_id(intent_id) = NextId.after(@retrieval.nodes(intent_id), prefix: "n")
    end
  end
end
