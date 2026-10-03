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
        qualified(intent_id, path, documents.current_revision(intent_id, path))
      end

      def fetch(reference)
        fields = address.fields_for(reference)
        address.verify_store(fields)
        row = documents.fetch(fields)

        qualified(fields.fetch(:intent_id), fields.fetch(:path), row.fetch("sha256")).merge(body: row.fetch("body"))
      end

      def qualified_reference(intent_id, path, sha256) = qualified(intent_id, path, sha256)

      def fetch_passage(reference, position)
        document = fetch(reference)
        document.merge(position:, **documents.passage(document, position))
      end

      private

      attr_reader :address, :documents

      def qualified(intent_id, path, revision) = address.qualified(intent_id, path, revision)
    end
  end
end
