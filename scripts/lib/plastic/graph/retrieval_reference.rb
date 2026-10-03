# frozen_string_literal: true

require_relative "retrieval_address"
require_relative "retrieval_document_reader"

module Plastic
  module Graph
    # Resolves qualified document references within one retrieval store.
    class RetrievalReference
      def initialize(databases, store:, origin:)
        @address = RetrievalAddress.new(store)
        @documents = RetrievalDocumentReader.new(databases.fetch(:knowledge), origin.id)
      end

      def reference(intent_id, path)
        identity = DocumentIdentity.new(intent_id, path)
        qualified(identity, documents.current_revision(*identity.deconstruct))
      end

      def fetch(reference)
        fields = address.fields_for(reference)
        address.verify_store(fields)
        row = documents.fetch(fields)

        identity = DocumentIdentity.new(fields.fetch(:intent_id), fields.fetch(:path))
        qualified(identity, row.fetch("sha256")).merge(body: row.fetch("body"))
      end

      def search_reference(row) = qualified_reference(*row.values_at("intent_id", "path", "sha256"))

      def qualified_reference(intent_id, path, revision) = qualified(DocumentIdentity.new(intent_id, path), revision)

      def fetch_passage(reference, position)
        document = fetch(reference)
        document.merge(position:, **documents.passage(document, position))
      end

      private

      attr_reader :address, :documents

      # Identifies one document independently of its current or historical revision.
      DocumentIdentity = Data.define(:intent_id, :path)

      def qualified(identity, revision) = address.qualified(*identity.deconstruct, revision)
    end
  end
end
