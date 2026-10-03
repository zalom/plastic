# frozen_string_literal: true

require_relative "evidence_text"

module Plastic
  module Graph
    # Compares derived evidence rows with immutable document revisions.
    class EvidenceIntegrityAudit
      def report(snapshot) = { repairable: drift?(snapshot), missing: missing(snapshot) }

      private

      def missing(snapshot)
        revisions = snapshot.fetch(:revisions)
        snapshot.fetch(:documents).filter_map do |document|
          "#{document.intent_id}:#{document.path} has no immutable revision" unless revisions.any? { |revision| revision.matches?(document) }
        end
      end

      def drift?(snapshot) = %i[heads passages fts].any? { |name| expected(snapshot, name).sort != actual(snapshot, name).sort }

      def expected(snapshot, name)
        documents = snapshot.fetch(:documents)
        { heads: documents.map(&:head_values), passages: snapshot.fetch(:revisions).flat_map(&:passage_values), fts: documents.flat_map { |document| fts_values(document) } }.fetch(name)
      end

      def actual(snapshot, name)
        rows = snapshot.fetch(name).map(&:values)
        (name == :heads) ? rows.map { |row| row.values_at(0, 1, 2) } : rows
      end

      def fts_values(document) = document.fts_rows(nil).map { |row| row.values_at(:intent_id, :path, :body, :sha256, :position) }
    end
  end
end
