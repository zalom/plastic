# frozen_string_literal: true

require_relative "intent"
require_relative "cluster"
require_relative "document"
require_relative "savepoint"
require_relative "node"
require_relative "edge"
require_relative "ruling"
require_relative "kept_file"

module Plastic
  module Graph
    # Where each kind of row lives: the record, the database, the table, the
    # columns and the order. A read with no intent id reads every intent.
    Source = Data.define(:record, :database, :table, :columns, :order)

    # The rows of one source that this installation wrote.
    class Source
      def read(databases, **values) = databases.fetch(database).rows(sql, **values).map { |row| record.from_h(row) }

      def sql = "SELECT #{columns} FROM #{table} WHERE origin_id = :origin AND " \
                "(:intent_id IS NULL OR intent_id = :intent_id) ORDER BY #{order}"
    end

    # The named sources RetrievalGraph#read picks from.
    SOURCES = {
      intents: Source.new(Intent, :work, "intents", "*", "intent_id"),
      clusters: Source.new(Cluster, :work, "clusters", "*", "name, intent_id"),
      documents: Source.new(Document, :knowledge, "documents", "*", "intent_id, path"),
      savepoints: Source.new(Savepoint, :work, "savepoints", "*", "intent_id, position"),
      nodes: Source.new(Node, :work, "nodes", "*", "intent_id, id"),
      edges: Source.new(Edge, :work, "edges", "*", 'intent_id, "from", "to", kind'),
      rulings: Source.new(Ruling, :knowledge, "rulings", "*", "intent_id, id"),
      kept_files: Source.new(KeptFile, :references, "sqlar", "name, mode, mtime, sz, intent_id, sha256, origin_id",
        "intent_id, name")
    }.freeze
  end
end
