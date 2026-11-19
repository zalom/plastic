# frozen_string_literal: true

require "json"

module Plastic
  module Graph
    # The document_revisions rows that migration 20261119000000 keeps in legacy.db before it drops the table: the earlier
    # texts, those no document_heads row names, of the paths the sync `selection` reads and of the store-level documents.
    # A down rebuilds the current texts from documents and document_heads, so those are not kept.
    class EarlierRevisions
      TABLE = "document_revisions"
      EARLIER = <<~SQL
        SELECT r.rowid AS id, r.intent_id, r.path FROM main.document_revisions r WHERE NOT EXISTS (SELECT 1 FROM main.document_heads h
          WHERE h.sha256 = r.sha256 AND h.intent_id = r.intent_id AND h.path = r.path AND h.origin_id = r.origin_id)
      SQL
      CHOSEN = "rowid IN (SELECT value FROM json_each(?))"
      PRESENT = "SELECT count(*) FROM main.sqlite_master WHERE type = 'table' AND name = 'document_revisions'"

      def initialize(connection, selection)
        @connection = connection
        @selection = selection
      end

      # Keeps the chosen rows through `keep`, which takes a table, a condition and its values. A store with no such table keeps nothing.
      def call(keep)
        keep.call(TABLE, CHOSEN, [JSON.generate(chosen)]) if @connection.get_first_value(PRESENT).positive?
      end

      private

      def chosen = @connection.read(EARLIER).select { |row| read?(row) }.map { |row| row.fetch("id") }

      def read?(row)
        intent_id = row.fetch("intent_id")
        intent_id.empty? || @selection.read?(row.fetch("path"), intent_id:)
      end
    end
  end
end
