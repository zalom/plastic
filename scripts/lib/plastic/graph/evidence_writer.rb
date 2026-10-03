# frozen_string_literal: true

require_relative "evidence_document"
require_relative "evidence_rows"
require_relative "evidence_removal"

module Plastic
  module Graph
    # Writes one immutable text revision and its current derived search rows.
    class EvidenceWriter
      def initialize(database, origin_id, after_passages: -> {})
        @database = database
        @origin_id = origin_id
        @after_passages = after_passages
      end

      def write(intent_id, path, body)
        document = EvidenceDocument.new(intent_id, path, body)
        @database.transaction { |batch| apply_document(batch, document) }
      end

      def apply(batch, ...)
        document = EvidenceDocument.new(...)
        apply_document(batch, document)
      end

      def remove(intent_id, path)
        @database.transaction { |batch| EvidenceRemoval.new(batch, @origin_id).remove(intent_id, path) }
      end

      private

      def apply_document(batch, document)
        EvidenceRows.new(batch, document, @origin_id).write { @after_passages.call }
      end
    end
  end
end
