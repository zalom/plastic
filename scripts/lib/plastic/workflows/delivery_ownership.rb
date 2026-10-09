# frozen_string_literal: true

module Plastic
  module Workflows
    # Whether another live session holds the delivery lock of the intent.
    module DeliveryOwnership
      def self.problem(context)
        id = context.intent_id
        lock = context.retrieval.lock(id)
        holder = lock&.session_id
        return unless holder && holder != context.session && lock.live?

        "intent #{id} is locked by session #{holder}"
      end
    end
  end
end
