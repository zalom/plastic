# frozen_string_literal: true

require "json"
require_relative "evidence/integrity_records"

module Plastic
  module Graph
    module Retrieval
      # Rebuilds the derived passages and search entries in the retrieval file from the documents of knowledge.
      class Index
        DOCUMENTS_SQL = "SELECT intent_id, path, body, updated_at FROM documents WHERE origin_id = :origin"
        PASSAGE_SQL = "INSERT OR IGNORE INTO document_passages (sha256, intent_id, path, position, body, line_start, line_end, origin_id) " \
                      "VALUES (:sha256, :intent_id, :path, :position, :body, :line_start, :line_end, :origin_id)"
        ENTRY_SQL = "INSERT INTO document_fts (body, intent_id, path, sha256, position, origin_id) VALUES (:body, :intent_id, :path, :sha256, :position, :origin_id)"
        # The condition that narrows the documents and the cleared rows, with its parameters; empty, it takes them all.
        Scope = Data.define(:sql, :params) do
          def self.intents(intent_ids) = new(" AND intent_id IN (SELECT value FROM json_each(:intent_ids))", { intent_ids: JSON.generate(intent_ids) })

          def documents(store, origin_id) = store.rows(DOCUMENTS_SQL + sql, origin: origin_id, **params)

          def clear(batch, origin_id)
            %w[document_fts document_passages].each { |table| batch.add("DELETE FROM #{table} WHERE origin_id = :origin#{sql}", origin: origin_id, **params) }
          end
        end
        EVERY = Scope.new("", {})

        def initialize(store, origin_id)
          @store = store
          @origin_id = origin_id
        end

        # Every document of the origin.
        def rebuild = replace(EVERY)

        # The documents of the intents `intent_ids`, in one pass; with none, nothing changes.
        def rebuild_intents(intent_ids) = (replace(Scope.intents(intent_ids)) unless intent_ids.empty?)

        private

        def replace(scope)
          documents = scope.documents(@store, @origin_id).map { |row| Evidence::IntegrityDocument.from_row(row) }
          inserts = documents.flat_map { |document| document.passage_rows(@origin_id).map { |row| [PASSAGE_SQL, row] } } +
            documents.flat_map { |document| document.fts_rows(@origin_id).map { |row| [ENTRY_SQL, row] } }
          @store.rebuilding { |batch| rebuild_into(batch, inserts, scope) }
        end

        def rebuild_into(batch, inserts, scope)
          scope.clear(batch, @origin_id)
          inserts.each { |sql, row| batch.add(sql, **row) }
        end
      end
    end
  end
end
