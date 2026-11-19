# frozen_string_literal: true

require_relative "../../evidence/text"

module Plastic
  module Graph
    module Retrieval
      class Evidence
        # Compares derived evidence rows with the current documents.
        class IntegrityAudit
          # Compares one derived table's canonical rows with its stored rows.
          TableComparison = Data.define(:name, :snapshot) do
            def expected
              { heads: documents.map(&:head_values), passages: documents.flat_map(&:passage_values),
                fts: documents.flat_map { |document| FtsProjection.new(document).values } }.fetch(name)
            end

            def actual
              rows = snapshot.fetch(name).map(&:values)
              (name == :heads) ? rows.map { |row| row.values_at(0, 1, 2) } : rows
            end

            def drift? = expected.sort != actual.sort

            private

            def documents = snapshot.fetch(:documents)
          end

          # Projects one document's passages into the FTS table's row order.
          FtsProjection = Data.define(:document) do
            def values = document.fts_rows(nil).map { |row| row.values_at(:intent_id, :path, :body, :sha256, :position) }
          end

          # Produces the public audit report from one immutable snapshot.
          Assessment = Data.define(:snapshot) do
            def report = { repairable: comparisons.any?(&:drift?) }

            private

            def comparisons = %i[heads passages fts].map { |name| TableComparison.new(name, snapshot) }
          end

          def self.report(snapshot) = Assessment.new(snapshot).report
        end
      end
    end
  end
end
