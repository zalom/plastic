# frozen_string_literal: true

require_relative "evidence_text"

module Plastic
  module Graph
    # Compares derived evidence rows with immutable document revisions.
    class EvidenceIntegrityAudit
      def report(snapshot) = { repairable: drift?(snapshot), missing: missing(snapshot) }

      private

      def missing(snapshot)
        revisions = snapshot.fetch(:revisions).map { |row| row.values_at("intent_id", "path", "body", "sha256") }
        snapshot.fetch(:documents).filter_map do |document|
          "#{document.fetch("intent_id")}:#{document.fetch("path")} has no immutable revision" unless revisions.include?(document.values_at("intent_id", "path", "body", "sha256"))
        end
      end

      def drift?(snapshot) = %i[heads passages fts].any? { |name| expected(snapshot, name).sort != actual(snapshot, name).sort }

      def expected(snapshot, name)
        documents = snapshot.fetch(:documents)
        { heads: documents.map { |row| row.values_at("intent_id", "path", "sha256") }, passages: snapshot.fetch(:revisions).flat_map { |row| passage_values(row) }, fts: documents.flat_map { |row| fts_values(row) } }.fetch(name)
      end

      def actual(snapshot, name)
        rows = snapshot.fetch(name).map(&:values)
        (name == :heads) ? rows.map { |row| row.values_at(0, 1, 2) } : rows
      end

      def passages(row) = EvidenceText.passages(EvidenceText.extract_with_lines(row.fetch("path"), row.fetch("body")))

      def passage_values(row) = passages(row).map { |passage| [row.fetch("sha256"), row.fetch("intent_id"), row.fetch("path"), *passage.values_at(:position, :body, :line_start, :line_end)] }

      def fts_values(row) = passages(row).map { |passage| [row.fetch("intent_id"), row.fetch("path"), passage.fetch(:body), row.fetch("sha256"), passage.fetch(:position)] }
    end
  end
end
