# frozen_string_literal: true

require_relative "evidence_text"

module Plastic
  module Graph
    # Compares derived evidence rows with immutable document revisions.
    class EvidenceIntegrityAudit
      # Compares one derived table's canonical rows with its stored rows.
      TableComparison = Data.define(:name, :snapshot) do
        def expected
          { heads: documents.map(&:head_values), passages: revisions.flat_map(&:passage_values),
            fts: documents.flat_map { |document| FtsProjection.new(document).values } }.fetch(name)
        end

        def actual
          rows = snapshot.fetch(name).map(&:values)
          (name == :heads) ? rows.map { |row| row.values_at(0, 1, 2) } : rows
        end

        def drift? = expected.sort != actual.sort

        private

        def documents = snapshot.fetch(:documents)
        def revisions = snapshot.fetch(:revisions)
      end

      # Projects one document's passages into the FTS table's row order.
      FtsProjection = Data.define(:document) do
        def values = document.fts_rows(nil).map { |row| row.values_at(:intent_id, :path, :body, :sha256, :position) }
      end

      # Identifies the immutable revision that belongs to one current document.
      MembershipKey = Data.define(:intent_id, :path, :body, :digest) do
        def self.document(document) = new(document.intent_id, document.path, document.body, document.digest)
        def self.revision(revision) = new(revision.intent_id, revision.path, revision.body, revision.sha256)
      end

      # Confirms that every current document has its exact immutable revision.
      ImmutableMembership = Data.define(:documents, :keys) do
        def missing
          documents.filter_map do |document|
            "#{document.intent_id}:#{document.path} has no immutable revision" unless keys.include?(MembershipKey.document(document))
          end
        end
      end

      # Produces the public audit report from one immutable snapshot.
      Assessment = Data.define(:snapshot) do
        def report
          { repairable: comparisons.any?(&:drift?), missing: membership.missing }
        end

        private

        def membership
          revisions = snapshot.fetch(:revisions).map { |revision| MembershipKey.revision(revision) }.to_set
          ImmutableMembership.new(snapshot.fetch(:documents), revisions)
        end

        def comparisons = %i[heads passages fts].map { |name| TableComparison.new(name, snapshot) }
      end

      def self.report(snapshot) = Assessment.new(snapshot).report
    end
  end
end
