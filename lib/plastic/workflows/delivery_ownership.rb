# frozen_string_literal: true

module Plastic
  module Workflows
    # Whether another live session holds the delivery lock of the intent.
    module DeliveryOwnership
      def self.problem(context)
        lock = foreign_lock(context)
        "intent #{context.intent_id} is locked by session #{lock.session_id}" if lock
      end

      # The live lock on the intent when another session holds it, or nil.
      def self.foreign_lock(context)
        retrieval = context.retrieval
        lock = retrieval.lock(context.intent_id)
        lock if lock && lock.session_id != context.session && retrieval.liveness(lock).live?
      end
    end
  end
end
