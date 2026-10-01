# frozen_string_literal: true

require_relative "sql"

module Plastic
  module Graph
    # Writes one intent's nodes: adds one, and moves one through its states.
    # Each move is a guarded UPDATE, so two moves of the same node cannot
    # both win; the one that finds no row back learns the state from a
    # fresh read.
    class NodeWriter
      RETRY_CAP = 3

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

      def remove_node(intent_id:, id:, reason:)
        moved(intent_id:, id:, to: "removed", from: %w[open], set: { reason: })
      end

      # Returns [:claimed, node], [:capped, node] or [:refused, node].
      def claim_node(intent_id:, id:, by:)
        current = @retrieval.node(intent_id, id)
        return [:refused, nil] unless current
        return capped(intent_id:, id:) if current.state == "open" && current.retries >= RETRY_CAP

        node = moved(intent_id:, id:, to: "claimed", from: %w[open], set: { by:, retries: SQL::Raw.new("retries + 1") })
        node ? [:claimed, node] : [:refused, refetched(intent_id, id)]
      end

      def release_node(intent_id:, id:) = moved(intent_id:, id:, to: "open", from: %w[claimed failed])

      def done_node(intent_id:, id:, **fields)
        moved(intent_id:, id:, to: "done", from: %w[claimed], set: fields)
      end

      def fail_node(intent_id:, id:, reason:)
        moved(intent_id:, id:, to: "failed", from: %w[claimed], set: { reason: })
      end

      def park_node(intent_id:, id:, question:)
        moved(intent_id:, id:, to: "parked", from: %w[claimed], set: { question: })
      end

      def answer_node(intent_id:, id:, answer:)
        moved(intent_id:, id:, to: "open", from: %w[parked], set: { answer:, retries: 0 })
      end

      private

      def refetched(intent_id, id) = @retrieval.node(intent_id, id)

      def capped(intent_id:, id:)
        node = moved(intent_id:, id:, to: "parked", from: %w[open],
          set: { question: "claimed 3 times; the owner decides" })
        [:capped, node]
      end

      def moved(intent_id:, id:, **move)
        sql = move_sql(move.fetch(:to), move.fetch(:from), move.fetch(:set, {}))
        rows = @databases.fetch(:work).transaction do |batch|
          batch.write(:nodes, sql, intent_id:, id:, origin: @retrieval.origin_id)
        end
        rows.any? ? @retrieval.node(intent_id, id) : nil
      end

      def move_sql(to, from, set)
        values = { state: to, updated_at: Plastic.now }.merge(set)
        <<~SQL
          UPDATE nodes SET #{SQL.set(values)}
          WHERE intent_id = :intent_id AND id = :id AND origin_id = :origin AND state IN (#{SQL.list(from)})
          RETURNING id
        SQL
      end

      def next_id(intent_id)
        highest = @retrieval.nodes(intent_id).filter_map { |node| node.id[/\An(\d+)\z/, 1]&.to_i }.max || 0
        "n#{highest + 1}"
      end
    end
  end
end
