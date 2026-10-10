# frozen_string_literal: true

require "json"

module Plastic
  module Workflows
    # Writes a discovery manifest as a row of the owning store, then prints the intent's files.
    class DiscoveryPersistence
      def self.persist(context, document)
        new(context, JSON.pretty_generate(document)).persist
      end

      def initialize(context, body)
        @context = context
        @body = body
      end

      def persist
        intent_id = @context.intent_id
        @context.database(:knowledge).transaction do |batch|
          batch.put(:retrieval_discoveries, { intent_id:, data: @body, updated_at: Plastic.now })
        end
      end
    end
  end
end
