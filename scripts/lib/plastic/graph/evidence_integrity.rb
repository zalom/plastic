# frozen_string_literal: true

require "digest"
require_relative "evidence_writer"
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
        report = report()
        raise EvidenceLost, report.fetch(:missing).join("; ") unless report.fetch(:missing).empty?

        rebuild_with_retry
        report
      end

      def report
        current = rows
        { repairable: drift?(current), missing: missing(current) }
      end

      private

      def rebuild
        current = rows
        @before_rebuild.call
        @database.transaction do |batch|
          guard(batch, current)
          clear(batch)
          current.fetch(:revisions).each { |revision| rebuild_passages(batch, revision) }
          current.fetch(:documents).each { |document| rebuild_current(batch, document) }
        end
      end

      def rebuild_with_retry
        rebuild
      rescue Database::Error => error
        raise unless error.message.include?("integer overflow")

        rebuild
      end

      def guard(batch, current)
        expected = current.fetch(:documents)
        conditions = expected.map do |document|
          "EXISTS (SELECT 1 FROM documents WHERE origin_id = #{SQL.literal(@origin_id)} AND intent_id = #{SQL.literal(document.fetch("intent_id"))} AND path = #{SQL.literal(document.fetch("path"))} AND body = #{SQL.literal(document.fetch("body"))})"
        end
        condition = ["(SELECT count(*) FROM documents WHERE origin_id = #{SQL.literal(@origin_id)}) = #{expected.size}", *conditions].join(" AND ")
        batch.add("SELECT CASE WHEN #{condition} THEN 1 ELSE abs(-9223372036854775808) END")
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
        EvidenceWriter.new(nil, @origin_id).apply(batch, document.fetch("intent_id"), document.fetch("path"), document.fetch("body"))
      end

      def rows
        { documents: documents, revisions: select("document_revisions", "intent_id, path, body, sha256"),
          heads: select("document_heads", "intent_id, path, sha256"),
          passages: select("document_passages", "sha256, position, body, line_start, line_end"),
          fts: select("document_fts", "intent_id, path, body, sha256, position") }
      end

      def documents
        select("documents", "intent_id, path, body").map do |row|
          row.merge("sha256" => Digest::SHA256.hexdigest(row.fetch("body")))
        end
      end

      def select(table, columns)
        @database.rows("SELECT #{columns} FROM #{table} WHERE origin_id = :origin", origin: @origin_id)
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

      def expected(current, name)
        { heads: current.fetch(:documents).map { |row| row.values_at("intent_id", "path", "sha256") },
          passages: current.fetch(:revisions).flat_map { |row| passage_values(row) },
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
