# frozen_string_literal: true

require "digest"

module Plastic
  module Graph
    # Writes one immutable text revision and its current derived search rows.
    class EvidenceWriter
      def initialize(database, origin_id)
        @database = database
        @origin_id = origin_id
      end

      def write(intent_id, path, body)
        @database.transaction { |batch| apply(batch, intent_id, path, body) }
      end

      def apply(batch, intent_id, path, body) = write_rows(batch, intent_id, path, body, Digest::SHA256.hexdigest(body))

      private

      def write_rows(batch, intent_id, path, body, sha256)
        now = Plastic.now
        row = { intent_id:, path:, body:, sha256:, now: }
        batch.put(:documents, { intent_id:, path:, body:, updated_at: now })
        revision(batch, row)
        current_rows(batch, row)
      end

      def revision(batch, row)
        intent_id, path, body, sha256, now = row.values_at(:intent_id, :path, :body, :sha256, :now)
        batch.add("INSERT OR IGNORE INTO document_revisions (sha256, intent_id, path, body, created_at, origin_id) VALUES (:sha256, :intent_id, :path, :body, :created_at, :origin_id)",
          sha256:, intent_id:, path:, body:, created_at: now, origin_id: @origin_id)
        batch.add("INSERT OR IGNORE INTO document_passages (sha256, position, body, line_start, line_end, origin_id) VALUES (:sha256, 1, :body, 1, :line_end, :origin_id)",
          sha256:, body:, line_end: body.lines.size, origin_id: @origin_id)
      end

      def current_rows(batch, row)
        intent_id, path, body, sha256, now = row.values_at(:intent_id, :path, :body, :sha256, :now)
        batch.put(:document_heads, { intent_id:, path:, sha256:, updated_at: now })
        batch.add("DELETE FROM document_fts WHERE intent_id = :intent_id AND path = :path AND origin_id = :origin_id",
          intent_id:, path:, origin_id: @origin_id)
        batch.add("INSERT INTO document_fts (body, intent_id, path, sha256, position, origin_id) VALUES (:body, :intent_id, :path, :sha256, 1, :origin_id)",
          body:, intent_id:, path:, sha256:, origin_id: @origin_id)
      end
    end
  end
end
