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
        entries.select { |entry| searchable?(entry) }.each do |entry|
          writer.write(intent_id, entry.fetch(:path), entry.fetch(:data).dup.force_encoding(Encoding::UTF_8))
        end
      end

      private

      attr_reader :classifier, :database, :origin_id

      def writer = EvidenceWriter.new(database, origin_id)

      def searchable?(entry) = entry[:kind] == "file" && classifier.classify(entry.fetch(:path), entry.fetch(:data)) == :text
    end
  end
end
