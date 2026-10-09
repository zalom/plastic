# frozen_string_literal: true

require_relative "knowledge/intent"
require_relative "work/cluster"
require_relative "knowledge/document"
require_relative "knowledge/legacy_intents_data"
require_relative "work/savepoint"
require_relative "work/node"
require_relative "work/edge"
require_relative "work/approval"
require_relative "work/verdict"
require_relative "knowledge/ruling"
require_relative "knowledge/archive/kept_file"

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
      intents: Source.new(Knowledge::Intent, :work, "intents", "*", "intent_id"),
      clusters: Source.new(Work::Cluster, :work, "clusters", "*", "name, intent_id"),
      documents: Source.new(Knowledge::Document, :knowledge, "documents", "*", "intent_id, path"),
      legacy_intents_data: Source.new(Knowledge::LegacyIntentsData, :knowledge, "legacy_intents_data", "*", "intent_id, path"),
      savepoints: Source.new(Work::Savepoint, :work, "savepoints", "*", "intent_id, position"),
      nodes: Source.new(Work::Node, :work, "nodes", "*", "intent_id, id"),
      edges: Source.new(Work::Edge, :work, "edges", "*", 'intent_id, "from", "to", kind'),
      approvals: Source.new(Work::Approval, :work, "approvals", "*", "intent_id"),
      verdicts: Source.new(Work::Verdict, :work, "verdicts", "*", "intent_id, round"),
      rulings: Source.new(Knowledge::Ruling, :knowledge, "rulings", "*", "intent_id, id"),
      kept_files: Source.new(Knowledge::Archive::KeptFile, :references, "sqlar", "name, mode, mtime, sz, intent_id, sha256, origin_id",
        "intent_id, name")
    }.freeze
  end
end
