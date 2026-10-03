# frozen_string_literal: true

require "digest"

module Plastic
  module Graph
    # Captures canonical and derived evidence rows from one origin.
    class EvidenceIntegritySnapshot
      TABLES = { revisions: ["document_revisions", "intent_id, path, body, sha256"], heads: ["document_heads", "intent_id, path, sha256"], passages: ["document_passages", "sha256, intent_id, path, position, body, line_start, line_end"], fts: ["document_fts", "intent_id, path, body, sha256, position"] }.freeze

      def initialize(database, origin_id)
        @database = database
        @origin_id = origin_id
      end

      def capture(source = @database)
        TABLES.to_h { |name, (table, columns)| [name, select(source, table, columns)] }.merge(documents: documents(source))
      end

      private

      def documents(source)
        select(source, "documents", "intent_id, path, body, updated_at").map { |row| row.merge("sha256" => Digest::SHA256.hexdigest(row.fetch("body"))) }
      end

      def select(source, table, columns)
        sql = SQL.bind("SELECT #{columns} FROM #{table} WHERE origin_id = :origin", origin: @origin_id)
        source.respond_to?(:sets) ? source.sets(sql).first || [] : source.rows(sql)
      end
    end
  end
end
