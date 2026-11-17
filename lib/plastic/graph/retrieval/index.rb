# frozen_string_literal: true

require_relative "evidence/integrity_records"

module Plastic
  module Graph
    module Retrieval
      # Rebuilds the derived passages and search entries in the retrieval file from the documents and revisions of knowledge.
      class Index
        REVISIONS_SQL = "SELECT intent_id, path, body, sha256 FROM document_revisions WHERE origin_id = :origin"
        DOCUMENTS_SQL = "SELECT intent_id, path, body, updated_at FROM documents WHERE origin_id = :origin"
        PASSAGE_SQL = "INSERT OR IGNORE INTO document_passages (sha256, intent_id, path, position, body, line_start, line_end, origin_id) " \
                      "VALUES (:sha256, :intent_id, :path, :position, :body, :line_start, :line_end, :origin_id)"
        ENTRY_SQL = "INSERT INTO document_fts (body, intent_id, path, sha256, position, origin_id) VALUES (:body, :intent_id, :path, :sha256, :position, :origin_id)"

        def initialize(store, origin_id)
          @store = store
          @origin_id = origin_id
        end

        # Every document of the origin.
        def rebuild = replace(nil)

        # The documents of one intent.
        def rebuild_intent(intent_id) = replace(intent_id)

        private

        def replace(intent_id)
          inserts = passage_rows(intent_id).map { |row| [PASSAGE_SQL, row] } + entry_rows(intent_id).map { |row| [ENTRY_SQL, row] }
          @store.rebuilding { |batch| rebuild_into(batch, intent_id, inserts) }
        end

        def passage_rows(intent_id) = read(REVISIONS_SQL, intent_id).flat_map { |row| Evidence::IntegrityRevision.from_row(row).passage_rows(@origin_id) }

        def entry_rows(intent_id) = read(DOCUMENTS_SQL, intent_id).flat_map { |row| Evidence::IntegrityDocument.from_row(row).fts_rows(@origin_id) }

        def rebuild_into(batch, intent_id, inserts)
          clear(batch, intent_id)
          inserts.each { |sql, row| batch.add(sql, **row) }
        end

        def read(sql, intent_id)
          sql += " AND intent_id = :intent_id" if intent_id
          @store.rows(sql, origin: @origin_id, **{ intent_id: }.compact)
        end

        def clear(batch, intent_id)
          scope = intent_id ? " AND intent_id = :intent_id" : ""
          %w[document_fts document_passages].each { |table| batch.add("DELETE FROM #{table} WHERE origin_id = :origin#{scope}", origin: @origin_id, **{ intent_id: }.compact) }
        end
      end
    end
  end
end
