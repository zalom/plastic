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
