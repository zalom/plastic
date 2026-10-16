# frozen_string_literal: true

require_relative "../graph/work/next_offer"

module Plastic
  module Workflows
    # Gives a workflow the why and handoff_text facts of the intent's go-ahead: the owner instruction until the approval row exists.
    module GoAhead
      def self.record(context)
        _command, why, handoff = Graph::Work::NextOffer.go_ahead_offer(context.retrieval, context.intent_id)
        context[:why] = why
        context[:handoff_text] = handoff
      end

      def reads_go_ahead
        read("read the go-ahead") { |context| GoAhead.record(context) }
      end
    end
  end
end
