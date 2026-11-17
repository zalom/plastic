# frozen_string_literal: true

module Plastic
  module Graph
    module SchemaStore1
      # The declared schema of each store database as store migration 1 made it,
      # written out. It never changes: a later change to the schema is a later
      # migration. Each text is the statements for one database file.
      module Layout
        TEXT = {
          work: <<~SQL,
            CREATE TABLE IF NOT EXISTS "intents"("id" INTEGER PRIMARY KEY AUTOINCREMENT, "intent_id" TEXT NOT NULL, "parent_id" TEXT, "ref" TEXT, "origin_id" TEXT NOT NULL, "slug" TEXT NOT NULL, "title" TEXT NOT NULL, "kind" TEXT, "status" TEXT NOT NULL CHECK(status IN ('open', 'in_progress', 'parked', 'future', 'done', 'abandoned')), "disposition" TEXT, "reason" TEXT, "opened_at" TEXT, "closed_at" TEXT, "updated_at" TEXT, UNIQUE("intent_id", "origin_id"));
            CREATE TABLE IF NOT EXISTS "clusters"("name" TEXT NOT NULL, "intent_id" TEXT NOT NULL, "origin_id" TEXT NOT NULL, UNIQUE("name", "intent_id", "origin_id"));
            CREATE TABLE IF NOT EXISTS "nodes"("intent_id" TEXT NOT NULL, "id" TEXT NOT NULL, "kind" TEXT, "title" TEXT, "criterion" TEXT, "state" TEXT, "by" TEXT, "input" TEXT, "output" TEXT, "question" TEXT, "answer" TEXT, "reason" TEXT, "judge" TEXT, "verdict" TEXT, "findings" TEXT, "retries" INTEGER, "updated_at" TEXT, "origin_id" TEXT NOT NULL, UNIQUE("intent_id", "id", "origin_id"));
            CREATE TABLE IF NOT EXISTS "edges"("intent_id" TEXT NOT NULL, "from" TEXT NOT NULL, "to" TEXT NOT NULL, "kind" TEXT NOT NULL, "origin_id" TEXT NOT NULL, UNIQUE("intent_id", "from", "to", "kind", "origin_id"));
            CREATE TABLE IF NOT EXISTS "savepoints"("intent_id" TEXT NOT NULL, "position" INTEGER NOT NULL, "at" TEXT, "text" TEXT NOT NULL, "origin_id" TEXT NOT NULL, "session_id" TEXT, UNIQUE("intent_id", "position", "origin_id"));
            CREATE TABLE IF NOT EXISTS "completions"("intent_id" TEXT NOT NULL, "origin_id" TEXT NOT NULL, "at" TEXT NOT NULL, "session_id" TEXT NOT NULL, "judge" TEXT NOT NULL, "criteria" TEXT NOT NULL, "evidence" TEXT NOT NULL, "outcome_sha256" TEXT NOT NULL, UNIQUE("intent_id", "origin_id"));
            CREATE TABLE IF NOT EXISTS "printed"("path" TEXT NOT NULL, "sha256" TEXT NOT NULL, "at" TEXT NOT NULL, "origin_id" TEXT NOT NULL, UNIQUE("path"));
            CREATE TABLE IF NOT EXISTS "changes"("seq" INTEGER PRIMARY KEY AUTOINCREMENT, "table" TEXT NOT NULL, "key" TEXT NOT NULL, "operation" TEXT NOT NULL CHECK(operation IN ('put', 'remove')), "row" TEXT, "at" TEXT NOT NULL, "origin_id" TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS "roadmaps"("slug" TEXT NOT NULL, "title" TEXT NOT NULL, "goal" TEXT, "opened_at" TEXT, "updated_at" TEXT, "origin_id" TEXT NOT NULL, UNIQUE("slug", "origin_id"));
            CREATE TABLE IF NOT EXISTS "batches"("roadmap" TEXT NOT NULL, "position" INTEGER NOT NULL, "title" TEXT NOT NULL, "goal" TEXT, "done" TEXT, "updated_at" TEXT, "origin_id" TEXT NOT NULL, UNIQUE("roadmap", "position", "origin_id"));
            CREATE TABLE IF NOT EXISTS "roadmap_items"("roadmap" TEXT NOT NULL, "item" TEXT NOT NULL, "batch" INTEGER NOT NULL, "position" INTEGER NOT NULL, "title" TEXT, "goal" TEXT, "done" TEXT, "intent_id" TEXT, "mark" TEXT, "updated_at" TEXT, "origin_id" TEXT NOT NULL, UNIQUE("roadmap", "item", "origin_id"));
            CREATE TABLE IF NOT EXISTS "roadmap_edges"("roadmap" TEXT NOT NULL, "from" TEXT NOT NULL, "to" TEXT NOT NULL, "kind" TEXT NOT NULL, "origin_id" TEXT NOT NULL, UNIQUE("roadmap", "from", "to", "origin_id"));
            CREATE TABLE IF NOT EXISTS "roadmap_log"("roadmap" TEXT NOT NULL, "position" INTEGER NOT NULL, "at" TEXT, "text" TEXT NOT NULL, "session_id" TEXT, "origin_id" TEXT NOT NULL, UNIQUE("roadmap", "position", "origin_id"));
            CREATE TABLE IF NOT EXISTS "archives"("intent_id" TEXT NOT NULL, "at" TEXT, "origin_id" TEXT NOT NULL, "restored_at" TEXT, "session_id" TEXT, UNIQUE("intent_id", "origin_id"));
            CREATE TABLE IF NOT EXISTS "archive_entries"("intent_id" TEXT NOT NULL, "path" TEXT NOT NULL, "origin_id" TEXT NOT NULL, "kind" TEXT NOT NULL, "mode" INTEGER, "mtime" TEXT, "data" BLOB, UNIQUE("intent_id", "path", "origin_id"));
            CREATE TABLE IF NOT EXISTS "approvals"("intent_id" TEXT NOT NULL, "origin_id" TEXT NOT NULL, "at" TEXT, "session_id" TEXT, UNIQUE("intent_id", "origin_id"));
            CREATE TABLE IF NOT EXISTS "verdicts"("intent_id" TEXT NOT NULL, "round" INTEGER NOT NULL, "origin_id" TEXT NOT NULL, "verdict" TEXT NOT NULL, "findings" TEXT NOT NULL, "at" TEXT, "session_id" TEXT, UNIQUE("intent_id", "round", "origin_id"));
            UPDATE "nodes" SET "state" = 'needs_info' WHERE "state" = 'parked';
          SQL
          knowledge: <<~SQL,
            CREATE TABLE IF NOT EXISTS "documents"("intent_id" TEXT NOT NULL, "path" TEXT NOT NULL, "body" TEXT NOT NULL, "updated_at" TEXT, "origin_id" TEXT NOT NULL, UNIQUE("intent_id", "path", "origin_id"));
            CREATE TABLE IF NOT EXISTS "legacy_intents_data"("intent_id" TEXT NOT NULL, "path" TEXT NOT NULL, "body" TEXT NOT NULL, "updated_at" TEXT, "origin_id" TEXT NOT NULL, UNIQUE("intent_id", "path", "origin_id"));
            CREATE TABLE IF NOT EXISTS "document_revisions"("sha256" TEXT NOT NULL, "intent_id" TEXT NOT NULL, "path" TEXT NOT NULL, "body" TEXT NOT NULL, "created_at" TEXT NOT NULL, "origin_id" TEXT NOT NULL, UNIQUE("sha256", "intent_id", "path", "origin_id"));
            CREATE TABLE IF NOT EXISTS "document_heads"("intent_id" TEXT NOT NULL, "path" TEXT NOT NULL, "sha256" TEXT NOT NULL, "updated_at" TEXT NOT NULL, "origin_id" TEXT NOT NULL, UNIQUE("intent_id", "path", "origin_id"));
            CREATE TABLE IF NOT EXISTS "document_passages"("sha256" TEXT NOT NULL, "intent_id" TEXT NOT NULL, "path" TEXT NOT NULL, "position" INTEGER NOT NULL, "body" TEXT NOT NULL, "line_start" INTEGER NOT NULL, "line_end" INTEGER NOT NULL, "origin_id" TEXT NOT NULL, UNIQUE("sha256", "intent_id", "path", "position", "origin_id"));
            CREATE VIRTUAL TABLE IF NOT EXISTS "document_fts" USING fts5(body, intent_id UNINDEXED, path UNINDEXED, sha256 UNINDEXED, position UNINDEXED, origin_id UNINDEXED);
            CREATE TABLE IF NOT EXISTS "retrieval_schema"("name" TEXT NOT NULL, "version" INTEGER NOT NULL, "completed_at" TEXT, UNIQUE("name"));
            CREATE TABLE IF NOT EXISTS "retrieval_backfills"("name" TEXT NOT NULL, "origin_id" TEXT NOT NULL, "version" INTEGER NOT NULL, "completed_at" TEXT NOT NULL, UNIQUE("name", "origin_id"));
            CREATE TABLE IF NOT EXISTS "retrieval_contexts"("intent_id" TEXT NOT NULL, "origin_id" TEXT NOT NULL, "data" TEXT, "updated_at" TEXT NOT NULL, UNIQUE("intent_id", "origin_id"));
            CREATE TABLE IF NOT EXISTS "retrieval_discoveries"("intent_id" TEXT NOT NULL, "origin_id" TEXT NOT NULL, "data" TEXT, "updated_at" TEXT NOT NULL, UNIQUE("intent_id", "origin_id"));
            CREATE TABLE IF NOT EXISTS "rulings"("intent_id" TEXT NOT NULL, "id" TEXT NOT NULL, "text" TEXT NOT NULL, "supersedes" TEXT, "at" TEXT, "session_id" TEXT, "origin_id" TEXT NOT NULL, UNIQUE("intent_id", "id", "origin_id"));
            CREATE TABLE IF NOT EXISTS "links"("from_ref" TEXT NOT NULL, "to_ref" TEXT NOT NULL, "kind" TEXT NOT NULL, "at" TEXT, "origin_id" TEXT NOT NULL, UNIQUE("from_ref", "to_ref", "kind", "origin_id"));
            CREATE TABLE IF NOT EXISTS "printed"("path" TEXT NOT NULL, "sha256" TEXT NOT NULL, "at" TEXT NOT NULL, "origin_id" TEXT NOT NULL, UNIQUE("path"));
            CREATE TABLE IF NOT EXISTS "changes"("seq" INTEGER PRIMARY KEY AUTOINCREMENT, "table" TEXT NOT NULL, "key" TEXT NOT NULL, "operation" TEXT NOT NULL CHECK(operation IN ('put', 'remove')), "row" TEXT, "at" TEXT NOT NULL, "origin_id" TEXT NOT NULL);
            INSERT OR IGNORE INTO "retrieval_schema" ("name", "version") VALUES ('retrieval', 1);
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
          references: <<~SQL
            CREATE TABLE IF NOT EXISTS "sqlar"("name" TEXT PRIMARY KEY, "mode" INT, "mtime" INT, "sz" INT, "data" BLOB, "intent_id" TEXT, "sha256" TEXT, "origin_id" TEXT NOT NULL, UNIQUE("name"));
            CREATE TABLE IF NOT EXISTS "printed"("path" TEXT NOT NULL, "sha256" TEXT NOT NULL, "at" TEXT NOT NULL, "origin_id" TEXT NOT NULL, UNIQUE("path"));
            CREATE TABLE IF NOT EXISTS "changes"("seq" INTEGER PRIMARY KEY AUTOINCREMENT, "table" TEXT NOT NULL, "key" TEXT NOT NULL, "operation" TEXT NOT NULL CHECK(operation IN ('put', 'remove')), "row" TEXT, "at" TEXT NOT NULL, "origin_id" TEXT NOT NULL);
          SQL
        }.freeze
      end
    end
  end
end
