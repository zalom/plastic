# frozen_string_literal: true

module Plastic
  module Graph
    module RetrievalSchema
      TABLES = {
        document_revisions: [%i[sha256 origin_id], { sha256: :kept, intent_id: :kept, path: :kept,
                                                     body: :kept, created_at: :kept, origin_id: :kept }],
        document_heads: [%i[intent_id path origin_id], { intent_id: :kept, path: :kept,
                                                         sha256: :kept, updated_at: :kept, origin_id: :kept }],
        document_passages: [%i[sha256 position origin_id], { sha256: :kept, position: "INTEGER NOT NULL",
                                                             body: :kept, line_start: "INTEGER NOT NULL",
                                                             line_end: "INTEGER NOT NULL", origin_id: :kept }],
        retrieval_schema: [%i[name], { name: :kept, version: "INTEGER NOT NULL", completed_at: :text }]
      }.freeze

      FTS = {
        document_fts: 'CREATE VIRTUAL TABLE IF NOT EXISTS "document_fts" USING fts5(body, intent_id UNINDEXED, path UNINDEXED, sha256 UNINDEXED, position UNINDEXED, origin_id UNINDEXED);'
      }.freeze
    end
  end
end
