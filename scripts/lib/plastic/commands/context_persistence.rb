# frozen_string_literal: true

module Plastic
  module Commands
    # Writes the context only to the owning store.
    class ContextPersistence
      def initialize(graphs:, scope:, intent_id:)
        @graphs = graphs
        @scope = scope
        @intent_id = intent_id
      end

      def persist(document)
        body = JSON.pretty_generate(document)
        persist_database(body)
        persist_context(body)
        document
      end

      private

      attr_reader :graphs, :scope, :intent_id

      def persist_database(body)
        updated_at = Plastic.now
        graphs.databases.fetch(:knowledge).transaction do |batch|
          batch.put(:retrieval_contexts, { intent_id:, data: body, updated_at: })
        end
      end

      def persist_context(body)
        directory = File.dirname(context_path)
        FileUtils.mkdir_p(directory)
        Tempfile.create(["context", ".json"], directory) do |file|
          file.write(body)
          file.flush
          File.rename(file.path, context_path)
        end
      end

      def context_path = File.join(scope.root, "context", "#{intent_id}.json")
    end
  end
end
