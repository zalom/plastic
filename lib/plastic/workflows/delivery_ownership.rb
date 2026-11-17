# frozen_string_literal: true

module Plastic
  module Workflows
    # Whether another session holds a live claim on a node of the intent.
    module DeliveryOwnership
      def self.problem(context, now: Time.now)
        node = foreign_claim(context, now)
        "intent #{context.intent_id} has node #{node.id} claimed by session #{node.claimed_by}" if node
      end

      # A node of the intent that another session holds, its claim not lapsed at the time given, or nil.
      def self.foreign_claim(context, now)
        context.retrieval.claimed_nodes.find do |node|
          node.intent_id == context.intent_id && node.claimed_by != context.session && !node.lapsed?(now)
        end
      end
    end
  end
end
