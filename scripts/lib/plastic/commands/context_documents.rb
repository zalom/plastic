# frozen_string_literal: true

module Plastic
  module Commands
    # Reads the current context and discovery records from their owning store.
    class ContextDocuments
      LOCATIONS = {
        context: ["retrieval_contexts", "context"],
        discovery: ["retrieval_discoveries", "discovery"]
      }.freeze

      def initialize(graphs:, scope:, intent_id:)
        @graphs = graphs
        @scope = scope
        @intent_id = intent_id
      end

      def read(kind)
        table, directory = LOCATIONS.fetch(kind)
        row = knowledge.row("SELECT data FROM #{table} WHERE intent_id = :intent_id AND origin_id = :origin", **parameters)
        return JSON.parse(row.fetch("data")) if row

        JSON.parse(File.read(path(directory)))
      end

      private

      attr_reader :graphs, :scope, :intent_id

      def knowledge = graphs.databases.fetch(:knowledge)

      def parameters = { intent_id:, origin: graphs.retrieval.origin_id }

      def path(directory) = File.join(scope.root, directory, "#{intent_id}.json")
    end
  end
end
