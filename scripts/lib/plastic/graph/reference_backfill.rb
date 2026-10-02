# frozen_string_literal: true

require_relative "evidence_writer"

module Plastic
  module Graph
    # Imports eligible legacy attachments after the retrieval schema appears.
    class ReferenceBackfill
      def initialize(databases, origin_id)
        @knowledge = databases.fetch(:knowledge)
        @references = databases.fetch(:references)
        @origin_id = origin_id
      end

      def call = legacy_references.each { |row| write(row) }

      private

      def legacy_references
        @references.rows("SELECT name, data, intent_id FROM sqlar WHERE origin_id = :origin", origin: @origin_id)
          .select { |row| text?(row.fetch("data")) }
      end

      def write(row)
        path = row.fetch("name").split("/", 3).last
        return if head_exists?(row.fetch("intent_id"), path)

        EvidenceWriter.new(@knowledge, @origin_id).write(row.fetch("intent_id"), path, utf8(row.fetch("data")))
      end

      def head_exists?(intent_id, path)
        @knowledge.row("SELECT 1 FROM document_heads WHERE intent_id = :intent_id AND path = :path AND origin_id = :origin",
          intent_id:, path:, origin: @origin_id)
      end

      def text?(bytes) = utf8(bytes).valid_encoding? && !bytes.include?("\0")

      def utf8(bytes) = bytes.dup.force_encoding(Encoding::UTF_8)
    end
  end
end
