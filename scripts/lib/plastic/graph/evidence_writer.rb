# frozen_string_literal: true

require "digest"
require_relative "evidence_text"

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
        @database.transaction { |batch| apply(batch, intent_id, path, body) }
      end

      # Removes only the mutable current view. The immutable revision and its
      # passages remain available for an exact historical read.
      def remove(intent_id, path)
        @database.transaction do |batch|
          batch.remove(:documents, intent_id:, path:)
          batch.remove(:document_heads, intent_id:, path:)
          batch.add("DELETE FROM document_fts WHERE intent_id = :intent_id AND path = :path AND origin_id = :origin_id",
            intent_id:, path:, origin_id: @origin_id)
        end
      end

      def apply(batch, intent_id, path, body) = write_rows(batch, intent_id, path, body, Digest::SHA256.hexdigest(body))

      private

      def write_rows(batch, intent_id, path, body, sha256)
        now = Plastic.now
        row = { intent_id:, path:, body:, sha256:, now:, extraction: EvidenceText.extract_with_lines(path, body) }
        batch.put(:documents, { intent_id:, path:, body:, updated_at: now })
        revision(batch, row)
        current_rows(batch, row)
      end

      def revision(batch, row)
        intent_id, path, body, sha256, now = row.values_at(:intent_id, :path, :body, :sha256, :now)
        batch.add("INSERT OR IGNORE INTO document_revisions (sha256, intent_id, path, body, created_at, origin_id) VALUES (:sha256, :intent_id, :path, :body, :created_at, :origin_id)",
          sha256:, intent_id:, path:, body:, created_at: now, origin_id: @origin_id)
        EvidenceText.passages(row.fetch(:extraction)).each do |passage|
          batch.add("INSERT OR IGNORE INTO document_passages (sha256, intent_id, path, position, body, line_start, line_end, origin_id) VALUES (:sha256, :intent_id, :path, :position, :body, :line_start, :line_end, :origin_id)",
            sha256:, intent_id:, path:, position: passage.fetch(:position), body: passage.fetch(:body), line_start: passage.fetch(:line_start), line_end: passage.fetch(:line_end), origin_id: @origin_id)
        end
        @after_passages.call
      end

      def current_rows(batch, row)
        intent_id, path, _, sha256, now = row.values_at(:intent_id, :path, :body, :sha256, :now)
        batch.put(:document_heads, { intent_id:, path:, sha256:, updated_at: now })
        batch.add("DELETE FROM document_fts WHERE intent_id = :intent_id AND path = :path AND origin_id = :origin_id",
          intent_id:, path:, origin_id: @origin_id)
        EvidenceText.passages(row.fetch(:extraction)).each do |passage|
          batch.add("INSERT INTO document_fts (body, intent_id, path, sha256, position, origin_id) VALUES (:body, :intent_id, :path, :sha256, :position, :origin_id)",
            body: passage.fetch(:body), intent_id:, path:, sha256:, position: passage.fetch(:position), origin_id: @origin_id)
        end
      end
    end
  end
end
