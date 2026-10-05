# frozen_string_literal: true

module Plastic
  module Graph
    module Work
      # One intent's heading and node counts by state, ready for a status row.
      class IntentRow
        def initialize(retrieval, intent)
          @retrieval = retrieval
          @intent = intent
        end

        def to_a = [@intent.heading, Node::Counts.new(@retrieval.nodes(@intent.intent_id)).line]
      end
    end
  end
end
