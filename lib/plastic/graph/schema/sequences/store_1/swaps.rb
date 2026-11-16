# frozen_string_literal: true

module Plastic
  module Graph
    module SchemaStore1
      # The statements of the three table rebuilds that store migration 1 runs
      # on a database of an older release, written out. They never change.
      module Swaps
        INTENTS = <<~SQL
          CREATE TABLE IF NOT EXISTS "intents"("id" INTEGER PRIMARY KEY AUTOINCREMENT, "intent_id" TEXT NOT NULL, "parent_id" TEXT, "ref" TEXT, "origin_id" TEXT NOT NULL, "slug" TEXT NOT NULL, "title" TEXT NOT NULL, "kind" TEXT, "status" TEXT NOT NULL CHECK(status IN ('open', 'in_progress', 'parked', 'future', 'done', 'abandoned')), "disposition" TEXT, "reason" TEXT, "opened_at" TEXT, "closed_at" TEXT, "updated_at" TEXT, UNIQUE("intent_id", "origin_id"));
        SQL

        INTENT_STATES_COPY = <<~SQL
          INSERT INTO intents (id, intent_id, parent_id, ref, origin_id, slug, title, kind, status, disposition, reason, opened_at, closed_at, updated_at)
          SELECT id, intent_id, parent_id, ref, origin_id, slug, title, kind,
            CASE status WHEN 'active' THEN 'in_progress' ELSE status END,
            CASE status
              WHEN 'done' THEN 'delivered'
              WHEN 'abandoned' THEN CASE
                WHEN disposition IN ('superseded', 'cancelled') THEN disposition
                WHEN disposition LIKE '%superseded by%' THEN 'superseded'
                ELSE 'cancelled' END
              ELSE NULL END,
            CASE WHEN disposition IS NOT NULL AND disposition NOT IN ('delivered', 'superseded', 'cancelled') THEN disposition END,
            opened_at, closed_at, updated_at
          FROM intents_legacy;
          DELETE FROM sqlite_sequence WHERE name = 'intents';
          INSERT INTO sqlite_sequence (name, seq) SELECT 'intents', seq FROM sqlite_sequence WHERE name = 'intents_legacy';
        SQL

        REVISIONS = <<~SQL
          CREATE TABLE IF NOT EXISTS "document_revisions"("sha256" TEXT NOT NULL, "intent_id" TEXT NOT NULL, "path" TEXT NOT NULL, "body" TEXT NOT NULL, "created_at" TEXT NOT NULL, "origin_id" TEXT NOT NULL, UNIQUE("sha256", "intent_id", "path", "origin_id"));
        SQL

        REVISIONS_COPY = <<~SQL
          INSERT INTO document_revisions (sha256, intent_id, path, body, created_at, origin_id)
          SELECT sha256, intent_id, path, body, created_at, origin_id FROM document_revisions_legacy;
        SQL

        PASSAGES = <<~SQL
          CREATE TABLE IF NOT EXISTS "document_passages"("sha256" TEXT NOT NULL, "intent_id" TEXT NOT NULL, "path" TEXT NOT NULL, "position" INTEGER NOT NULL, "body" TEXT NOT NULL, "line_start" INTEGER NOT NULL, "line_end" INTEGER NOT NULL, "origin_id" TEXT NOT NULL, UNIQUE("sha256", "intent_id", "path", "position", "origin_id"));
        SQL

        PASSAGES_COPY = <<~SQL
          INSERT INTO document_passages (sha256, intent_id, path, position, body, line_start, line_end, origin_id)
          SELECT p.sha256, r.intent_id, r.path, p.position, p.body, p.line_start, p.line_end, p.origin_id
          FROM document_passages_legacy p JOIN document_revisions r ON r.sha256 = p.sha256 AND r.origin_id = p.origin_id;
        SQL

        SEARCH_TRIGGER_DROPS = <<~SQL
          DROP TRIGGER IF EXISTS "document_heads_search_insert";
          DROP TRIGGER IF EXISTS "document_heads_search_update";
          DROP TRIGGER IF EXISTS "document_heads_search_delete";
        SQL

        SEARCH_TRIGGER_CREATES = <<~SQL
          CREATE TRIGGER IF NOT EXISTS "document_heads_search_insert" AFTER INSERT ON "document_heads" BEGIN
            INSERT INTO "document_fts" ("body", "intent_id", "path", "sha256", "position", "origin_id")
            SELECT p."body", p."intent_id", p."path", p."sha256", p."position", p."origin_id" FROM "document_passages" p
            WHERE p."sha256" = NEW."sha256" AND p."intent_id" = NEW."intent_id" AND p."path" = NEW."path" AND p."origin_id" = NEW."origin_id";
          END;

          CREATE TRIGGER IF NOT EXISTS "document_heads_search_update" AFTER UPDATE ON "document_heads" BEGIN
            DELETE FROM "document_fts" WHERE "intent_id" = OLD."intent_id" AND "path" = OLD."path" AND "origin_id" = OLD."origin_id";
            INSERT INTO "document_fts" ("body", "intent_id", "path", "sha256", "position", "origin_id")
            SELECT p."body", p."intent_id", p."path", p."sha256", p."position", p."origin_id" FROM "document_passages" p
            WHERE p."sha256" = NEW."sha256" AND p."intent_id" = NEW."intent_id" AND p."path" = NEW."path" AND p."origin_id" = NEW."origin_id";
          END;

          CREATE TRIGGER IF NOT EXISTS "document_heads_search_delete" AFTER DELETE ON "document_heads" BEGIN
            DELETE FROM "document_fts" WHERE "intent_id" = OLD."intent_id" AND "path" = OLD."path" AND "origin_id" = OLD."origin_id";
          END;
        SQL
      end
    end
  end
end
