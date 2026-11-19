# frozen_string_literal: true

module Plastic
  module Graph
    # Builds a document_revisions row for each current document that has none, from documents and document_heads, so a
    # store that went down below migration 20261119000000 holds what the release before it wrote: a revision for every
    # head. Its search, its reads by revision and its integrity audit then find every document. Docs:
    # docs/contributing/MIGRATIONS.md.
    module RevisionRows
      TABLE = "document_revisions"
      SQL = <<~SQL
        INSERT INTO main.document_revisions (sha256, intent_id, path, body, created_at, origin_id)
        SELECT h.sha256, d.intent_id, d.path, d.body, h.updated_at, d.origin_id FROM main.documents d
        JOIN main.document_heads h ON h.intent_id = d.intent_id AND h.path = d.path AND h.origin_id = d.origin_id
        WHERE NOT EXISTS (SELECT 1 FROM main.document_revisions r WHERE r.sha256 = h.sha256 AND r.intent_id = d.intent_id
          AND r.path = d.path AND r.origin_id = d.origin_id)
      SQL

      # Writes the missing rows and answers how many it wrote, by table.
      def self.call(connection)
        connection.execute(SQL)
        { TABLE => connection.changes }
      end
    end
  end
end
