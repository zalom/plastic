# frozen_string_literal: true

require_relative "evidence_writer"
require_relative "evidence_text"

module Plastic
  module Graph
    # Adds searchable text from a durable archive snapshot to retrieval evidence.
    class ArchiveSnapshotIndex
      def initialize(database, origin_id)
        @database = database
        @origin_id = origin_id
        @classifier = EvidenceText
      end

      def index(intent_id, entries)
        entries.select { |entry| entry[:kind] == "file" }.each { |entry| index_file(intent_id, entry) }
      end

      private

      attr_reader :classifier, :database, :origin_id

      def writer = EvidenceWriter.new(database, origin_id)

      def index_file(intent_id, entry)
        path, data = entry.values_at(:path, :data)
        return unless classifier.classify(path, data) == :text

        writer.write(intent_id, path, data.dup.force_encoding(Encoding::UTF_8))
      end
    end
  end
end
