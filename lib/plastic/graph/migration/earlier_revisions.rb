# frozen_string_literal: true

module Plastic
  module Graph
    # The rows of a document_revisions table that a down cannot rebuild and a sync still reads: the earlier texts, those
    # no document_heads row names, of the paths the sync `selection` reads and of the store-level documents. A down
    # rebuilds the current texts from documents and document_heads.
    class EarlierRevisions
      EARLIER = <<~SQL
        SELECT r.rowid AS id, r.intent_id, r.path FROM %<table>s r WHERE NOT EXISTS (SELECT 1 FROM main.document_heads h
          WHERE h.sha256 = r.sha256 AND h.intent_id = r.intent_id AND h.path = r.path AND h.origin_id = r.origin_id)
      SQL

      def initialize(connection, selection)
        @connection = connection
        @selection = selection
      end

      # The rowids of those rows in `table`, a table name with its schema.
      def ids(table) = @connection.read(format(EARLIER, table:)).select { |row| read?(row) }.map { |row| row.fetch("id") }

      private

      def read?(row)
        intent_id = row.fetch("intent_id")
        intent_id.empty? || @selection.read?(row.fetch("path"), intent_id:)
      end
    end
  end
end
