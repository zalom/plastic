# frozen_string_literal: true

require "digest"

module Plastic
  module Graph
    # Captures canonical and derived evidence rows from one origin.
    class EvidenceIntegritySnapshot
      # An immutable revision that supplies derived passages.
      Revision = Data.define(:intent_id, :path, :body, :sha256) do
        def matches?(document) = [intent_id, path, body, sha256] == [document.intent_id, document.path, document.body, document.digest]
        def passages = EvidenceText.passages(EvidenceText.extract_with_lines(path, body))
        def passage_values = passages.map { |passage| [sha256, intent_id, path, *passage.values_at(:position, :body, :line_start, :line_end)] }
        def passage_rows(origin_id) = passages.map { |passage| { sha256:, intent_id:, path:, origin_id:, **passage } }
      end

      # A current document that supplies its head and FTS rows.
      Document = Data.define(:intent_id, :path, :body, :updated_at, :digest) do
        def passages = EvidenceText.passages(EvidenceText.extract_with_lines(path, body))
        def head_values = [intent_id, path, digest]
        def head_row(origin_id) = { intent_id:, path:, sha256: digest, updated_at:, origin_id: }
        def fts_rows(origin_id) = passages.map { |passage| { body: passage.fetch(:body), intent_id:, path:, sha256: digest, position: passage.fetch(:position), origin_id: } }
      end

      TABLES = { heads: ["document_heads", "intent_id, path, sha256"], passages: ["document_passages", "sha256, intent_id, path, position, body, line_start, line_end"], fts: ["document_fts", "intent_id, path, body, sha256, position"] }.freeze

      def initialize(database, origin_id)
        @database = database
        @origin_id = origin_id
      end

      def capture(source = @database)
        TABLES.to_h { |name, (table, columns)| [name, select(source, table, columns)] }.merge(revisions: revisions(source), documents: documents(source))
      end

      private

      def documents(source)
        select(source, "documents", "intent_id, path, body, updated_at").map do |row|
          Document.new(**row.transform_keys(&:to_sym), digest: Digest::SHA256.hexdigest(row.fetch("body")))
        end
      end

      def revisions(source)
        select(source, "document_revisions", "intent_id, path, body, sha256").map { |row| Revision.new(**row.transform_keys(&:to_sym)) }
      end

      def select(source, table, columns)
        sql = SQL.bind("SELECT #{columns} FROM #{table} WHERE origin_id = :origin", origin: @origin_id)
        source.respond_to?(:sets) ? source.sets(sql).first || [] : source.rows(sql)
      end
    end
  end
end
