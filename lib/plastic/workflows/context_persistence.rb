# frozen_string_literal: true

require "json"

module Plastic
  module Workflows
    # Writes the context as a row of the owning store, then prints the intent's files.
    class ContextPersistence
      def initialize(context)
        @context = context
      end

      def persist(document)
        intent_id = context.intent_id
        context.database(:knowledge).transaction do |batch|
          batch.put(:retrieval_contexts, { intent_id:, data: JSON.pretty_generate(document), updated_at: Plastic.now })
        end
        document
      end

      private

      attr_reader :context
    end
  end
end
