# frozen_string_literal: true

module Plastic
  module Graph
    module RetrievalSchema
      TABLES = {
        document_revisions: [%i[sha256 intent_id path origin_id], { sha256: :kept, intent_id: :kept, path: :kept,
                                                     body: :kept, created_at: :kept, origin_id: :kept }],
        document_heads: [%i[intent_id path origin_id], { intent_id: :kept, path: :kept,
                                                         sha256: :kept, updated_at: :kept, origin_id: :kept }],
        document_passages: [%i[sha256 intent_id path position origin_id], { sha256: :kept, intent_id: :kept, path: :kept,
                                                             position: "INTEGER NOT NULL", body: :kept, line_start: "INTEGER NOT NULL",
                                                             line_end: "INTEGER NOT NULL", origin_id: :kept }],
        retrieval_schema: [%i[name], { name: :kept, version: "INTEGER NOT NULL", completed_at: :text }],
        retrieval_backfills: [%i[name origin_id], { name: :kept, origin_id: :kept, version: "INTEGER NOT NULL", completed_at: :kept }],
        retrieval_contexts: [%i[intent_id origin_id], { intent_id: :kept, origin_id: :kept, data: :text, updated_at: :kept }],
        retrieval_discoveries: [%i[intent_id origin_id], { intent_id: :kept, origin_id: :kept, data: :text, updated_at: :kept }],
        architecture_receipts: [%i[provider origin_id], { provider: :kept, origin_id: :kept, data: :text, updated_at: :kept }]
      }.freeze

      FTS = {
        document_fts: 'CREATE VIRTUAL TABLE IF NOT EXISTS "document_fts" USING fts5(body, intent_id UNINDEXED, path UNINDEXED, sha256 UNINDEXED, position UNINDEXED, origin_id UNINDEXED);'
      }.freeze
    end
  end
end
