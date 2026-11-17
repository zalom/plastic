CREATE TABLE IF NOT EXISTS "routine_runs"("store" TEXT NOT NULL, "tool" TEXT NOT NULL, "subject" TEXT NOT NULL DEFAULT '', "at" TEXT, "finished" TEXT, "status" TEXT, "facts" TEXT, "next_command" TEXT, "because" TEXT, "exit_code" INTEGER, "started_at" TEXT, "updated_at" TEXT, "session_id" TEXT, UNIQUE("store", "tool", "subject"));
CREATE TABLE IF NOT EXISTS "sessions"("session_id" TEXT NOT NULL, "harness" TEXT, "store" TEXT, "directory" TEXT, "started_at" TEXT, "last_turn_at" TEXT, "ended_at" TEXT, "end_reason" TEXT, "note" TEXT, UNIQUE("session_id"));
ALTER TABLE "routine_runs" RENAME TO "command_runs";
DROP TABLE IF EXISTS "backups";
DROP TABLE IF EXISTS "locks";
CREATE TABLE IF NOT EXISTS "settings"("scope" TEXT NOT NULL, "key" TEXT NOT NULL, "value" TEXT NOT NULL, UNIQUE("scope", "key"));
CREATE TABLE IF NOT EXISTS "printed"("path" TEXT NOT NULL, "sha256" TEXT NOT NULL, "at" TEXT NOT NULL, "origin_id" TEXT NOT NULL, UNIQUE("path"));
