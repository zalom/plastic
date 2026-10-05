# frozen_string_literal: true

require "json"

module Plastic
  module Workflows
    # Reads the current context and discovery records from their owning store.
    class ContextDocuments
      LOCATIONS = {
        context: ["retrieval_contexts", "context"],
        discovery: ["retrieval_discoveries", "discovery"]
      }.freeze

      def initialize(context)
        @context = context
      end

      def read(kind)
        table, directory = LOCATIONS.fetch(kind)
        row = knowledge.row("SELECT data FROM #{table} WHERE intent_id = :intent_id AND origin_id = :origin", **parameters)
        return JSON.parse(row.fetch("data")) if row

        JSON.parse(File.read(path(directory)))
      end

      private

      attr_reader :context

      def knowledge = context.database(:knowledge)

      def parameters = { intent_id: context.intent_id, origin: context.retrieval.origin_id }

      def path(directory) = File.join(context.scope.root, directory, "#{context.intent_id}.json")
    end
  end
end
