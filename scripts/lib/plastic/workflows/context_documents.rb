# frozen_string_literal: true

require "json"

module Plastic
  module Workflows
    # Reads the current context and discovery records from the rows of their owning store.
    class ContextDocuments
      TABLES = { context: "retrieval_contexts", discovery: "retrieval_discoveries" }.freeze

      def initialize(context)
        @context = context
      end

      def read(kind)
        table = TABLES.fetch(kind)
        row = knowledge.row("SELECT data FROM #{table} WHERE intent_id = :intent_id AND origin_id = :origin", **parameters)
        raise Errno::ENOENT, "no saved #{kind} for intent #{context.intent_id}" unless row

        JSON.parse(row.fetch("data"))
      end

      private

      attr_reader :context

      def knowledge = context.database(:knowledge)

      def parameters = { intent_id: context.intent_id, origin: context.retrieval.origin_id }
    end
  end
end
