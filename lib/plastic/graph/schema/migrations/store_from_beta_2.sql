CREATE TABLE IF NOT EXISTS refs."sqlar"("name" TEXT PRIMARY KEY, "mode" INT, "mtime" INT, "sz" INT, "data" BLOB, "intent_id" TEXT, "sha256" TEXT, "origin_id" TEXT NOT NULL, UNIQUE("name"));
CREATE TABLE IF NOT EXISTS refs."printed"("path" TEXT NOT NULL, "sha256" TEXT NOT NULL, "at" TEXT NOT NULL, "origin_id" TEXT NOT NULL, UNIQUE("path"));

CREATE TABLE IF NOT EXISTS main."intents"("id" INTEGER PRIMARY KEY AUTOINCREMENT, "intent_id" TEXT NOT NULL, "parent_id" TEXT, "ref" TEXT, "origin_id" TEXT NOT NULL, "slug" TEXT NOT NULL, "title" TEXT NOT NULL, "kind" TEXT, "status" TEXT NOT NULL CHECK(status IN ('open', 'in_progress', 'parked', 'future', 'done', 'abandoned')), "disposition" TEXT, "reason" TEXT, "opened_at" TEXT, "closed_at" TEXT, "updated_at" TEXT, UNIQUE("intent_id", "origin_id"));
CREATE TABLE IF NOT EXISTS main."clusters"("name" TEXT NOT NULL, "intent_id" TEXT NOT NULL, "origin_id" TEXT NOT NULL, UNIQUE("name", "intent_id", "origin_id"));
CREATE TABLE IF NOT EXISTS main."completions"("intent_id" TEXT NOT NULL, "origin_id" TEXT NOT NULL, "at" TEXT NOT NULL, "session_id" TEXT NOT NULL, "judge" TEXT NOT NULL, "criteria" TEXT NOT NULL, "evidence" TEXT NOT NULL, "outcome_sha256" TEXT NOT NULL, UNIQUE("intent_id", "origin_id"));
CREATE TABLE IF NOT EXISTS main."approvals"("intent_id" TEXT NOT NULL, "origin_id" TEXT NOT NULL, "at" TEXT, "session_id" TEXT, UNIQUE("intent_id", "origin_id"));
CREATE TABLE IF NOT EXISTS main."verdicts"("intent_id" TEXT NOT NULL, "round" INTEGER NOT NULL, "origin_id" TEXT NOT NULL, "verdict" TEXT NOT NULL, "findings" TEXT NOT NULL, "at" TEXT, "session_id" TEXT, UNIQUE("intent_id", "round", "origin_id"));
CREATE TABLE IF NOT EXISTS main."archives"("intent_id" TEXT NOT NULL, "at" TEXT, "origin_id" TEXT NOT NULL, "restored_at" TEXT, "session_id" TEXT, UNIQUE("intent_id", "origin_id"));
CREATE TABLE IF NOT EXISTS main."archive_entries"("intent_id" TEXT NOT NULL, "path" TEXT NOT NULL, "origin_id" TEXT NOT NULL, "kind" TEXT NOT NULL, "mode" INTEGER, "mtime" TEXT, "data" BLOB, UNIQUE("intent_id", "path", "origin_id"));
CREATE TABLE IF NOT EXISTS main."sqlar"("name" TEXT PRIMARY KEY, "mode" INT, "mtime" INT, "sz" INT, "data" BLOB, "intent_id" TEXT, "sha256" TEXT, "origin_id" TEXT NOT NULL, UNIQUE("name"));CREATE TABLE IF NOT EXISTS work."work_log"("intent_id" TEXT NOT NULL, "position" INTEGER NOT NULL, "at" TEXT, "phase" TEXT NOT NULL DEFAULT '', "node" TEXT NOT NULL DEFAULT '', "session_id" TEXT, "kind" TEXT NOT NULL, "path" TEXT NOT NULL DEFAULT '', "sha256" TEXT NOT NULL DEFAULT '', "text" TEXT NOT NULL DEFAULT '', "origin_id" TEXT NOT NULL, UNIQUE("intent_id", "position", "origin_id"));
CREATE TABLE IF NOT EXISTS work."runs"("intent_id" TEXT NOT NULL, "node_id" TEXT NOT NULL, "number" INTEGER NOT NULL, "agent" TEXT NOT NULL DEFAULT '', "session_id" TEXT NOT NULL DEFAULT '', "started_at" TEXT, "ended_at" TEXT, "result" TEXT, "origin_id" TEXT NOT NULL, UNIQUE("intent_id", "node_id", "number", "origin_id"));
CREATE TABLE IF NOT EXISTS work."work_log"("intent_id" TEXT NOT NULL, "position" INTEGER NOT NULL, "at" TEXT, "phase" TEXT NOT NULL DEFAULT '', "node" TEXT NOT NULL DEFAULT '', "session_id" TEXT, "kind" TEXT NOT NULL, "path" TEXT NOT NULL DEFAULT '', "sha256" TEXT NOT NULL DEFAULT '', "text" TEXT NOT NULL DEFAULT '', "origin_id" TEXT NOT NULL, UNIQUE("intent_id", "position", "origin_id"));
ALTER TABLE work."nodes" ADD COLUMN "claimed_by" TEXT;
ALTER TABLE work."nodes" ADD COLUMN "claimed_at" TEXT;
ALTER TABLE work."nodes" ADD COLUMN "seen_at" TEXT;
ALTER TABLE work."nodes" ADD COLUMN "answered_at" TEXT;
INSERT INTO work."runs"("intent_id", "node_id", "number", "agent", "session_id", "started_at", "ended_at", "result", "origin_id")
  SELECT "intent_id", "id", 1, '', "by", "updated_at",
    CASE WHEN "state" = 'claimed' THEN NULL ELSE "updated_at" END,
    CASE WHEN "state" = 'claimed' THEN NULL WHEN "state" = 'open' THEN 'released' ELSE "state" END,
    "origin_id"
  FROM work."nodes" WHERE "by" IS NOT NULL AND "by" != '';
UPDATE work."nodes" SET "claimed_by" = "by", "claimed_at" = "updated_at" WHERE "state" = 'claimed' AND "by" IS NOT NULL AND "by" != '';
ALTER TABLE work."nodes" DROP COLUMN "by";
ALTER TABLE work."nodes" DROP COLUMN "retries";

INSERT INTO work."work_log"("intent_id", "position", "at", "phase", "node", "session_id", "kind", "path", "sha256", "text", "origin_id")
  SELECT "intent_id", "position", "at", '', '', "session_id", 'noted', '', '', "text", "origin_id" FROM work."savepoints";
DROP TABLE work."savepoints";

INSERT INTO main."intents"("id", "intent_id", "parent_id", "ref", "origin_id", "slug", "title", "kind", "status", "disposition", "reason", "opened_at", "closed_at", "updated_at") SELECT "id", "intent_id", "parent_id", "ref", "origin_id", "slug", "title", "kind", "status", "disposition", "reason", "opened_at", "closed_at", "updated_at" FROM work."intents";
DELETE FROM main.sqlite_sequence WHERE name = 'intents';
INSERT INTO main.sqlite_sequence(name, seq) SELECT name, seq FROM work.sqlite_sequence WHERE name = 'intents';
DELETE FROM work.sqlite_sequence WHERE name = 'intents';
DROP TABLE work."intents";
INSERT INTO main."clusters"("name", "intent_id", "origin_id") SELECT "name", "intent_id", "origin_id" FROM work."clusters";
DROP TABLE work."clusters";
INSERT INTO main."completions"("intent_id", "origin_id", "at", "session_id", "judge", "criteria", "evidence", "outcome_sha256") SELECT "intent_id", "origin_id", "at", "session_id", "judge", "criteria", "evidence", "outcome_sha256" FROM work."completions";
DROP TABLE work."completions";
INSERT INTO main."approvals"("intent_id", "origin_id", "at", "session_id") SELECT "intent_id", "origin_id", "at", "session_id" FROM work."approvals";
DROP TABLE work."approvals";
INSERT INTO main."verdicts"("intent_id", "round", "origin_id", "verdict", "findings", "at", "session_id") SELECT "intent_id", "round", "origin_id", "verdict", "findings", "at", "session_id" FROM work."verdicts";
DROP TABLE work."verdicts";
INSERT INTO main."archives"("intent_id", "at", "origin_id", "restored_at", "session_id") SELECT "intent_id", "at", "origin_id", "restored_at", "session_id" FROM work."archives";
DROP TABLE work."archives";
INSERT INTO main."archive_entries"("intent_id", "path", "origin_id", "kind", "mode", "mtime", "data") SELECT "intent_id", "path", "origin_id", "kind", "mode", "mtime", "data" FROM work."archive_entries";
DROP TABLE work."archive_entries";

INSERT OR IGNORE INTO main."printed"("path", "sha256", "at", "origin_id") SELECT "path", "sha256", "at", "origin_id" FROM work."printed";
INSERT OR IGNORE INTO main."printed"("path", "sha256", "at", "origin_id") SELECT "path", "sha256", "at", "origin_id" FROM refs."printed";
DROP TABLE work."printed";
DROP TABLE work."changes";
DROP TABLE main."changes";

DROP TRIGGER IF EXISTS main."document_heads_search_insert";
DROP TRIGGER IF EXISTS main."document_heads_search_update";
DROP TRIGGER IF EXISTS main."document_heads_search_delete";
DROP TABLE IF EXISTS main."document_fts";
DROP TABLE IF EXISTS main."document_passages";
DROP TABLE IF EXISTS main."retrieval_schema";
DROP TABLE IF EXISTS main."retrieval_backfills";

CREATE TABLE IF NOT EXISTS retrieval."document_passages"("sha256" TEXT NOT NULL, "intent_id" TEXT NOT NULL, "path" TEXT NOT NULL, "position" INTEGER NOT NULL, "body" TEXT NOT NULL, "line_start" INTEGER NOT NULL, "line_end" INTEGER NOT NULL, "origin_id" TEXT NOT NULL, UNIQUE("sha256", "intent_id", "path", "position", "origin_id"));
CREATE VIRTUAL TABLE IF NOT EXISTS retrieval."document_fts" USING fts5(body, intent_id UNINDEXED, path UNINDEXED, sha256 UNINDEXED, position UNINDEXED, origin_id UNINDEXED);

INSERT OR REPLACE INTO main."sqlar"("name", "mode", "mtime", "sz", "data", "intent_id", "sha256", "origin_id")
  SELECT "name", "mode", "mtime", "sz", "data", "intent_id", "sha256", "origin_id" FROM refs."sqlar";

CREATE TEMP TABLE "references_check"("ok" INTEGER CONSTRAINT "references.db rows missing from knowledge" CHECK("ok" = 1));
INSERT INTO temp."references_check"("ok") SELECT (SELECT count(*) FROM refs."sqlar" AS r JOIN main."sqlar" AS k ON k."name" = r."name" AND k."sha256" IS r."sha256") = (SELECT count(*) FROM refs."sqlar");
DROP TABLE temp."references_check";
