# frozen_string_literal: true

require_relative "source"
require_relative "link"

module Plastic
  module Graph
    # The read side of the work graph beyond a plain Source: one node by id,
    # the nodes ready to claim, the rulings of an intent, and the links a ref
    # carries.
    class WorkReader
      READY_NODES_SQL = <<~SQL
        SELECT * FROM nodes
        WHERE intent_id = :intent_id AND origin_id = :origin
          AND state = 'open'
          AND NOT EXISTS (
            SELECT 1 FROM edges JOIN nodes AS from_node
              ON from_node.intent_id = edges.intent_id AND from_node.id = edges."from"
            WHERE edges.intent_id = nodes.intent_id AND edges.kind = 'needs' AND edges."to" = nodes.id
              AND from_node.state IS NOT 'done'
          )
        ORDER BY id
      SQL

      LINKS_SQL = 'SELECT * FROM links WHERE origin_id = :origin AND (from_ref = :ref OR to_ref = :ref) ORDER BY "at"'

      def initialize(databases, origin:)
        @databases = databases
        @origin = origin
      end

      # Nodes of `intent_id` ready to run: state nil, empty or pending, with
      # every `needs` edge into them satisfied (graph/edge.rb: `to` waits
      # until `from` is done).
      def ready_nodes(intent_id)
        @databases.fetch(:work).rows(READY_NODES_SQL, intent_id:, origin: origin_id).map { |row| Node.from_h(row) }
      end

      def node(intent_id, id) = nodes(intent_id).find { |node| node.id == id }

      def rulings(intent_id = nil) = SOURCES.fetch(:rulings).read(@databases, origin: origin_id, intent_id:)

      # Links naming `ref` at either end: a ruling's ref today, any ref later.
      def links(ref) = @databases.fetch(:knowledge).rows(LINKS_SQL, origin: origin_id, ref:).map { |row| Link.from_h(row) }

      private

      def origin_id = @origin.id

      def nodes(intent_id) = SOURCES.fetch(:nodes).read(@databases, origin: origin_id, intent_id:)
    end
  end
end
