# frozen_string_literal: true

require_relative "integrity_records"
require_relative "integrity_sources"

module Plastic
  module Graph
    module Retrieval
      class Evidence
        # Captures canonical and derived evidence rows from one origin.
        class IntegritySnapshot
          TABLES = { heads: ["document_heads", "intent_id, path, sha256"], passages: ["document_passages", "sha256, intent_id, path, position, body, line_start, line_end"], fts: ["document_fts", "intent_id, path, body, sha256, position"] }.freeze

          def initialize(database, origin_id)
            @database = database
            @origin_id = origin_id
          end

          def capture = capture_with(Evidence::IntegrityDatabaseSource.new(@database))

          def capture_transaction(connection) = capture_with(Evidence::IntegrityTransactionSource.new(connection))

          private

          def capture_with(reader)
            TABLES.to_h { |name, (table, columns)| [name, select(reader, table, columns)] }.merge(revisions: revisions(reader), documents: documents(reader))
          end

          def documents(reader) = select(reader, "documents", "intent_id, path, body, updated_at").map { |row| Evidence::IntegrityDocument.from_row(row) }

          def revisions(reader) = select(reader, "document_revisions", "intent_id, path, body, sha256").map { |row| Evidence::IntegrityRevision.from_row(row) }

          def select(reader, table, columns)
            sql = SQL.bind("SELECT #{columns} FROM #{table} WHERE origin_id = :origin", origin: @origin_id)
            reader.rows(sql)
          end
        end
      end
    end
  end
end
