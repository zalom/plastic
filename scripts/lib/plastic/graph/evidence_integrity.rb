# frozen_string_literal: true

require "digest"
require_relative "evidence_text"

module Plastic
  module Graph
    # Diagnoses and rebuilds rows that can be derived from immutable evidence.
    class EvidenceIntegrity
      class EvidenceLost < StandardError; end

      def initialize(database, origin_id, before_rebuild: -> {})
        @database = database
        @origin_id = origin_id
        @before_rebuild = before_rebuild
      end

      def repair!
        @database.immediate_transaction do |batch, connection|
          @before_rebuild.call
          current = rows(connection)
          report = report_for(current)
          raise EvidenceLost, report.fetch(:missing).join("; ") unless report.fetch(:missing).empty?

          rebuild(batch, current)
        end
        report()
      end

      def report
        report_for(rows)
      end

      private

      def rebuild(batch, current)
        clear(batch)
        current.fetch(:revisions).each { |revision| rebuild_passages(batch, revision) }
        current.fetch(:documents).each { |document| rebuild_current(batch, document) }
      end

      def clear(batch)
        %w[document_heads document_passages document_fts].each do |table|
          batch.add("DELETE FROM #{table} WHERE origin_id = :origin", origin: @origin_id)
        end
      end

      def rebuild_passages(batch, revision)
        passages(revision).each do |passage|
          batch.add("INSERT INTO document_passages (sha256, position, body, line_start, line_end, origin_id) VALUES (:sha256, :position, :body, :line_start, :line_end, :origin_id)",
            sha256: revision.fetch("sha256"), origin_id: @origin_id, **passage)
        end
      end

      def rebuild_current(batch, document)
        sha256 = document.fetch("sha256")
        batch.add("INSERT INTO document_heads (intent_id, path, sha256, updated_at, origin_id) VALUES (:intent_id, :path, :sha256, :updated_at, :origin_id)",
          intent_id: document.fetch("intent_id"), path: document.fetch("path"), sha256:, updated_at: document.fetch("updated_at"), origin_id: @origin_id)
        passages(document).each do |passage|
          batch.add("INSERT INTO document_fts (body, intent_id, path, sha256, position, origin_id) VALUES (:body, :intent_id, :path, :sha256, :position, :origin_id)",
            body: passage.fetch(:body), intent_id: document.fetch("intent_id"), path: document.fetch("path"), sha256:, position: passage.fetch(:position), origin_id: @origin_id)
        end
      end

      def rows(connection = nil)
        { documents: documents(connection), revisions: select("document_revisions", "intent_id, path, body, sha256", connection),
          heads: select("document_heads", "intent_id, path, sha256", connection),
          passages: select("document_passages", "sha256, position, body, line_start, line_end", connection),
          fts: select("document_fts", "intent_id, path, body, sha256, position", connection) }
      end

      def documents(connection = nil)
        select("documents", "intent_id, path, body, updated_at", connection).map do |row|
          row.merge("sha256" => Digest::SHA256.hexdigest(row.fetch("body")))
        end
      end

      def select(table, columns, connection = nil)
        sql = SQL.bind("SELECT #{columns} FROM #{table} WHERE origin_id = :origin", origin: @origin_id)
        (connection || @database).then { |source| source.respond_to?(:sets) ? source.sets(sql).first || [] : source.rows(sql) }
      end

      def missing(current)
        current.fetch(:documents).filter_map do |document|
          "#{document.fetch("intent_id")}:#{document.fetch("path")} has no immutable revision" unless revision?(current, document)
        end
      end

      def revision?(current, document)
        current.fetch(:revisions).any? do |revision|
          revision.values_at("intent_id", "path", "body", "sha256") == document.values_at("intent_id", "path", "body", "sha256")
        end
      end

      def drift?(current)
        %i[heads passages fts].any? { |name| expected(current, name).sort != actual(current, name).sort }
      end

      def report_for(current) = { repairable: drift?(current), missing: missing(current) }

      def expected(current, name)
        { heads: current.fetch(:documents).map { |row| row.values_at("intent_id", "path", "sha256") },
          passages: current.fetch(:revisions).flat_map { |row| passage_values(row) }.uniq,
          fts: current.fetch(:documents).flat_map { |row| fts_values(row) } }.fetch(name)
      end

      def actual(current, name)
        rows = current.fetch(name).map(&:values)
        return rows unless name == :heads

        rows.map { |row| row.values_at(0, 1, 2) }
      end

      def passages(row)
        EvidenceText.passages(EvidenceText.extract_with_lines(row.fetch("path"), row.fetch("body")))
      end

      def passage_values(row)
        passages(row).map { |passage| [row.fetch("sha256"), *passage.values_at(:position, :body, :line_start, :line_end)] }
      end

      def fts_values(row) = passages(row).map { |passage| [row.fetch("intent_id"), row.fetch("path"), passage.fetch(:body), row.fetch("sha256"), passage.fetch(:position)] }
    end
  end
end
