# frozen_string_literal: true

module Plastic
  module Graph
    # One intent's heading and node counts by state, ready for a status row.
    class IntentRow
      def initialize(retrieval, intent)
        @retrieval = retrieval
        @intent = intent
      end

      def to_a = [@intent.heading, NodeCounts.new(@retrieval.nodes(@intent.intent_id)).line]
    end

    # One intent's node counts by state, rendered as a status line.
    class NodeCounts
      def initialize(nodes) = @nodes = nodes

      def line
        return "no nodes" if counts.empty?

        counts.map { |state, count| "#{state}: #{count}" }.join(", ")
      end

      private

      def counts = @nodes.group_by(&:state).transform_values(&:size)
    end
  end
end
