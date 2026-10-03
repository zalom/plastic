# frozen_string_literal: true

module Plastic
  module Graph
    # An immutable revision that supplies derived passages.
    EvidenceIntegrityRevision = Data.define(:intent_id, :path, :body, :sha256) do
      def self.from_row(row) = new(**row.transform_keys(&:to_sym))
      def matches?(document) = [intent_id, path, body, sha256] == [document.intent_id, document.path, document.body, document.digest]
      def passages = EvidenceText.passages(EvidenceText.extract_with_lines(path, body))
      def passage_values = passages.map { |passage| [sha256, intent_id, path, *passage.values_at(:position, :body, :line_start, :line_end)] }
      def passage_rows(origin_id) = passages.map { |passage| { sha256:, intent_id:, path:, origin_id:, **passage } }
    end

    # A current document that supplies its head and FTS rows.
    EvidenceIntegrityDocument = Data.define(:intent_id, :path, :body, :updated_at, :digest) do
      def self.from_row(row) = new(**row.transform_keys(&:to_sym), digest: Digest::SHA256.hexdigest(row.fetch("body")))
      def passages = EvidenceText.passages(EvidenceText.extract_with_lines(path, body))
      def head_values = [intent_id, path, digest]
      def head_row(origin_id) = { intent_id:, path:, sha256: digest, updated_at:, origin_id: }
      def fts_rows(origin_id) = passages.map { |passage| { body: passage.fetch(:body), intent_id:, path:, sha256: digest, position: passage.fetch(:position), origin_id: } }
    end
  end
end
