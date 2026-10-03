# frozen_string_literal: true

require_relative "evidence_text"

module Plastic
  module Graph
    # Rebuilds derived search rows from verified immutable evidence.
    class EvidenceIntegrityRebuilder
      def initialize(origin_id) = @origin_id = origin_id

      def rebuild(batch, snapshot)
        clear(batch)
        snapshot.fetch(:revisions).each { |revision| rebuild_passages(batch, revision) }
        snapshot.fetch(:documents).each { |document| rebuild_current(batch, document) }
      end

      private

      def clear(batch)
        %w[document_heads document_passages document_fts].each { |table| batch.add("DELETE FROM #{table} WHERE origin_id = :origin", origin: @origin_id) }
      end

      def rebuild_passages(batch, revision)
        passages(revision).each do |passage|
          batch.add("INSERT INTO document_passages (sha256, intent_id, path, position, body, line_start, line_end, origin_id) VALUES (:sha256, :intent_id, :path, :position, :body, :line_start, :line_end, :origin_id)", sha256: revision.fetch("sha256"), intent_id: revision.fetch("intent_id"), path: revision.fetch("path"), origin_id: @origin_id, **passage)
        end
      end

      def rebuild_current(batch, document)
        revision = document.fetch("sha256")
        intent_id = document.fetch("intent_id")
        path = document.fetch("path")
        batch.add("INSERT INTO document_heads (intent_id, path, sha256, updated_at, origin_id) VALUES (:intent_id, :path, :sha256, :updated_at, :origin_id)", intent_id:, path:, sha256: revision, updated_at: document.fetch("updated_at"), origin_id: @origin_id)
        passages(document).each do |passage|
          batch.add("INSERT INTO document_fts (body, intent_id, path, sha256, position, origin_id) VALUES (:body, :intent_id, :path, :sha256, :position, :origin_id)", body: passage.fetch(:body), intent_id:, path:, sha256: revision, position: passage.fetch(:position), origin_id: @origin_id)
        end
      end

      def passages(row) = EvidenceText.passages(EvidenceText.extract_with_lines(row.fetch("path"), row.fetch("body")))
    end
  end
end
