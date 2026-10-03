# frozen_string_literal: true

module Plastic
  module Commands
    # Writes context and architecture receipts only to the owning store.
    class ContextPersistence
      def initialize(graphs:, scope:, intent_id:)
        @graphs = graphs
        @scope = scope
        @intent_id = intent_id
      end

      def persist(document)
        body = JSON.pretty_generate(document)
        architecture = document.fetch("architecture")
        receipt = architecture["receipt"]
        persist_database(body, architecture, receipt)
        persist_receipt(architecture) if receipt
        persist_context(body)
        document
      end

      private

      attr_reader :graphs, :scope, :intent_id

      def persist_database(body, architecture, receipt)
        graphs.databases.fetch(:knowledge).transaction do |batch|
          batch.put(:retrieval_contexts, { intent_id:, data: body, updated_at: Plastic.now })
          batch.put(:architecture_receipts, { provider: architecture.fetch("provider"), data: JSON.pretty_generate(receipt), updated_at: Plastic.now }) if receipt
        end
      end

      def persist_receipt(architecture)
        path = receipt_path(architecture.fetch("provider"))
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.pretty_generate(architecture.fetch("receipt")))
      end

      def persist_context(body)
        FileUtils.mkdir_p(File.dirname(context_path))
        Tempfile.create(["context", ".json"], File.dirname(context_path)) do |file|
          file.write(body)
          file.flush
          File.rename(file.path, context_path)
        end
      end

      def context_path = File.join(scope.root, "context", "#{intent_id}.json")

      def receipt_path(provider) = File.join(scope.root, "architecture", "#{provider}.json")
    end
  end
end
