# frozen_string_literal: true

module Plastic
  module Workflows
    # Whether another live session holds the delivery lock of the intent.
    module DeliveryOwnership
      def self.problem(context)
        lock = context.retrieval.lock(context.intent_id)
        return unless lock && lock.session_id != context.session && lock.live?

        "intent #{context.intent_id} is locked by session #{lock.session_id}"
      end
    end
  end
end
