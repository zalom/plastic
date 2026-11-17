# frozen_string_literal: true

module Plastic
  module Graph
    # Store migration 2, frozen. A node no longer carries who holds it and how
    # often it was tried: it carries its claim and the time of the owner's last answer, and each try is one row of the
    # runs table. A node that had a holder gets one run, closed with the state
    # the node was in, and a claimed node keeps its claim and its run open. The
    # count of tries above one is not carried. Its statements are written out
    # and never call the live schema. The runner holds the write lock around it.
    module SchemaStore2
      TABLES = {
        "work_graph" => %w[intents clusters nodes edges savepoints completions printed changes roadmaps batches roadmap_items
          roadmap_edges roadmap_log archives archive_entries approvals verdicts runs],
        "knowledge_graph" => SchemaStore1::TABLES.fetch("knowledge_graph"),
        "references" => SchemaStore1::TABLES.fetch("references")
      }.freeze

      TEXT = {
        work: <<~SQL
          ALTER TABLE "nodes" ADD COLUMN "claimed_by" TEXT;
          ALTER TABLE "nodes" ADD COLUMN "claimed_at" TEXT;
          ALTER TABLE "nodes" ADD COLUMN "seen_at" TEXT;
          ALTER TABLE "nodes" ADD COLUMN "answered_at" TEXT;
          CREATE TABLE IF NOT EXISTS "runs"("intent_id" TEXT NOT NULL, "node_id" TEXT NOT NULL, "number" INTEGER NOT NULL, "agent" TEXT NOT NULL DEFAULT '', "session_id" TEXT NOT NULL DEFAULT '', "started_at" TEXT, "ended_at" TEXT, "result" TEXT, "origin_id" TEXT NOT NULL, UNIQUE("intent_id", "node_id", "number", "origin_id"));
          INSERT INTO "runs"("intent_id", "node_id", "number", "agent", "session_id", "started_at", "ended_at", "result", "origin_id")
            SELECT "intent_id", "id", 1, '', "by", "updated_at",
              CASE WHEN "state" = 'claimed' THEN NULL ELSE "updated_at" END,
              CASE WHEN "state" = 'claimed' THEN NULL WHEN "state" = 'open' THEN 'released' ELSE "state" END,
              "origin_id"
            FROM "nodes" WHERE "by" IS NOT NULL AND "by" != '';
          UPDATE "nodes" SET "claimed_by" = "by", "claimed_at" = "updated_at" WHERE "state" = 'claimed' AND "by" IS NOT NULL AND "by" != '';
          ALTER TABLE "nodes" DROP COLUMN "by";
          ALTER TABLE "nodes" DROP COLUMN "retries";
        SQL
      }.freeze

      module_function

      def texts = TEXT.values

      def apply(connection, key)
        return unless TEXT.key?(key)
        return unless connection.get_first_value("SELECT count(*) FROM pragma_table_info('nodes') WHERE name = 'by'").positive?

        connection.execute_batch(TEXT.fetch(key))
      end
    end
  end
end
