# frozen_string_literal: true

require_relative "intent_needs"

module Plastic
  module Graph
    module Work
      # One intent's heading and node counts by state, ready for a status row.
      class IntentRow
        def initialize(retrieval, intent, needs: IntentNeeds.new(retrieval))
          @retrieval = retrieval
          @intent = intent
          @needs = needs
        end

        def to_a = [@intent.heading, Node::Counts.new(@retrieval.structure.nodes(@intent.intent_id)).line, *waits]

        private

        # "waits on 2, 3" while an intent it needs is not finished, else nothing.
        def waits
          waiting = @needs.waiting_on(@intent.intent_id)
          waiting.empty? ? [] : ["waits on #{waiting.join(", ")}"]
        end
      end
    end
  end
end
