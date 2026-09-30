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
      def intents = records(Intent, :work, "SELECT * FROM intents WHERE origin_id = :origin").sort_by(&:segments)

      def intent(intent_id) = intents.find { |intent| intent.intent_id == intent_id }

      def clusters = records(Cluster, :work, "SELECT * FROM clusters WHERE origin_id = :origin ORDER BY name, intent_id")

      def documents(intent_id = nil) = of_intent(Document, :knowledge, "documents", intent_id, "path")

      def savepoints(intent_id = nil) = of_intent(Savepoint, :work, "savepoints", intent_id, "position")

      def nodes(intent_id = nil) = of_intent(Node, :work, "nodes", intent_id, "id")

      def edges(intent_id = nil) = of_intent(Edge, :work, "edges", intent_id, "\"from\", \"to\", kind")

      # Kept files with no bytes: a print compares the hash and reads the bytes only to write.
      def kept_files(intent_id = nil) = of_intent(KeptFile, :references, "sqlar", intent_id, "name", columns: KEPT_COLUMNS)

      def kept_file_data(name)
        row = @databases.fetch(:references).row("SELECT hex(data) AS data FROM sqlar WHERE name = :name", name:)
        [row.fetch("data")].pack("H*")
      end

      # The hash of every file printed from the store's rows, by path.
      def printed
        Schema::STORE.each_with_object({}) do |key, all|
          @databases.fetch(key).rows("SELECT path, sha256 FROM printed").each { |row| all[row["path"]] = row["sha256"] }
        end
      end

      KEPT_COLUMNS = "name, mode, mtime, sz, intent_id, sha256, origin_id"

      private

      def of_intent(record, key, table, intent_id, order, columns: "*")
        filter = intent_id ? " AND intent_id = :intent_id" : ""
        sql = "SELECT #{columns} FROM #{table} WHERE origin_id = :origin#{filter} ORDER BY intent_id, #{order}"
        records(record, key, sql, intent_id:)
      end

      def records(record, key, sql, **values)
        @databases.fetch(key).rows(sql, origin: origin_id, **values).map { |row| record.from_h(row) }
      end
    end
  end
end
