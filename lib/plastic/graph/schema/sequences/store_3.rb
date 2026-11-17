# frozen_string_literal: true

module Plastic
  module Graph
    # Store migration 3, frozen. The work log replaces the savepoint lines: each
    # savepoint row becomes one `noted` row of the work_log table with its text and
    # time, and the savepoints table is dropped. The log gains a write id, unique per origin, and the
    # work_log_pending table holds the lines a write owes before a drain turns them into rows. Its statements are written out and
    # never call the live schema. The runner holds the write lock around it.
    module SchemaStore3
      TABLES = {
        "work_graph" => %w[intents clusters nodes edges work_log work_log_pending completions printed changes roadmaps batches roadmap_items
          roadmap_edges roadmap_log archives archive_entries approvals verdicts runs],
        "knowledge_graph" => SchemaStore1::TABLES.fetch("knowledge_graph"),
        "references" => SchemaStore1::TABLES.fetch("references")
      }.freeze

      TEXT = {
        work: <<~SQL
          CREATE TABLE IF NOT EXISTS "work_log"("intent_id" TEXT NOT NULL, "position" INTEGER NOT NULL, "at" TEXT, "phase" TEXT NOT NULL DEFAULT '', "node" TEXT NOT NULL DEFAULT '', "session_id" TEXT, "kind" TEXT NOT NULL, "path" TEXT NOT NULL DEFAULT '', "sha256" TEXT NOT NULL DEFAULT '', "text" TEXT NOT NULL DEFAULT '', "origin_id" TEXT NOT NULL, "write_id" TEXT, UNIQUE("intent_id", "position", "origin_id"));
          INSERT INTO "work_log"("intent_id", "position", "at", "phase", "node", "session_id", "kind", "path", "sha256", "text", "origin_id")
            SELECT "intent_id", "position", "at", '', '', "session_id", 'noted', '', '', "text", "origin_id" FROM "savepoints";
          DROP TABLE "savepoints";
          CREATE UNIQUE INDEX IF NOT EXISTS "work_log_write_id" ON "work_log"("origin_id", "write_id") WHERE "write_id" IS NOT NULL;
          CREATE TABLE IF NOT EXISTS "work_log_pending"("write_id" TEXT NOT NULL, "intent_id" TEXT NOT NULL, "at" TEXT, "phase" TEXT NOT NULL DEFAULT '', "node" TEXT NOT NULL DEFAULT '', "session_id" TEXT, "kind" TEXT NOT NULL, "path" TEXT NOT NULL DEFAULT '', "sha256" TEXT NOT NULL DEFAULT '', "text" TEXT NOT NULL DEFAULT '', "origin_id" TEXT NOT NULL, UNIQUE("write_id"));
        SQL
      }.freeze

      module_function

      def texts = TEXT.values

      def apply(connection, key)
        return unless TEXT.key?(key)
        return if connection.get_first_value("SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = 'savepoints'").zero?

        connection.execute_batch(TEXT.fetch(key))
      end
    end
  end
end
