# frozen_string_literal: true

require_relative "../graph/work/next_offer"

module Plastic
  module Workflows
    # Gives a workflow the why and handoff_text facts of the intent's go-ahead: the owner instruction until the approval row exists.
    module GoAhead
      def reads_go_ahead
        read "read the go-ahead" do |context|
          _command, context[:why], context[:handoff_text] = Graph::Work::NextOffer.go_ahead_offer(context.retrieval, context.intent_id)
        end
      end
    end
  end
end
