# frozen_string_literal: true

require_relative "../routine_run"
require_relative "intent"
require_relative "cluster"
require_relative "document"
require_relative "savepoint"
require_relative "node"
require_relative "edge"
require_relative "kept_file"

module Plastic
  module Graph
    # The read side of the graphs: every check reads from here. Every method
    # returns records or plain values. Nothing here writes. A method that
    # takes an intent id reads every intent of the store when given none.
    class RetrievalGraph
      attr_reader :store

      def initialize(databases, store:, origin:)
        @databases = databases
        @store = store
        @origin = origin
      end

      def origin_id = @origin.id

      # The open or last routine run of one tool on one subject.
      def routine_run(tool, subject)
        row = @databases.fetch(:home).row("SELECT * FROM routine_runs WHERE store = :store AND tool = :tool AND " \
          "subject = :subject", store:, tool:, subject: subject.to_s)
        row && RoutineRun.from_row(row, subject)
      end

      # This installation's intents, in Luhmann order.
      def intents = read(:intents).sort_by(&:segments)

      def intent(intent_id) = intents.find { |intent| intent.intent_id == intent_id }

      def clusters = read(:clusters)

      def documents(intent_id = nil) = read(:documents, intent_id)

      def savepoints(intent_id = nil) = read(:savepoints, intent_id)

      def nodes(intent_id = nil) = read(:nodes, intent_id)

      def edges(intent_id = nil) = read(:edges, intent_id)

      # Kept files with no bytes: a print compares the hash and reads the bytes only to write.
      def kept_files(intent_id = nil) = read(:kept_files, intent_id)

      def kept_file_data(name)
        row = @databases.fetch(:references).row("SELECT hex(data) AS data FROM sqlar WHERE name = :name", name:)
        [row.fetch("data")].pack("H*")
      end

      # The hash of every file printed from the store's rows, by path.
      def printed
        Schema::STORE.flat_map { |key| @databases.fetch(key).rows("SELECT path, sha256 FROM printed") }
          .to_h { |row| row.values_at("path", "sha256") }
      end

      # Where each kind of row lives: the record, the database, the table, the
      # columns and the order. A read with no intent id reads every intent.
      Source = Data.define(:record, :database, :table, :columns, :order)

      # The rows of one source that this installation wrote.
      class Source
        def read(databases, **values) = databases.fetch(database).rows(sql, **values).map { |row| record.from_h(row) }

        def sql = "SELECT #{columns} FROM #{table} WHERE origin_id = :origin AND " \
                  "(:intent_id IS NULL OR intent_id = :intent_id) ORDER BY #{order}"
      end

      SOURCES = {
        intents: Source.new(Intent, :work, "intents", "*", "intent_id"),
        clusters: Source.new(Cluster, :work, "clusters", "*", "name, intent_id"),
        documents: Source.new(Document, :knowledge, "documents", "*", "intent_id, path"),
        savepoints: Source.new(Savepoint, :work, "savepoints", "*", "intent_id, position"),
        nodes: Source.new(Node, :work, "nodes", "*", "intent_id, id"),
        edges: Source.new(Edge, :work, "edges", "*", 'intent_id, "from", "to", kind'),
        kept_files: Source.new(KeptFile, :references, "sqlar", "name, mode, mtime, sz, intent_id, sha256, origin_id",
          "intent_id, name")
      }.freeze

      private

      def read(name, intent_id = nil) = SOURCES.fetch(name).read(@databases, origin: origin_id, intent_id:)
    end
  end
end
