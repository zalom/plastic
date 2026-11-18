CREATE TABLE IF NOT EXISTS "sqlar"("name" TEXT PRIMARY KEY, "mode" INT, "mtime" INT, "sz" INT, "data" BLOB, "intent_id" TEXT, "sha256" TEXT, "origin_id" TEXT NOT NULL, UNIQUE("name"));
CREATE TABLE IF NOT EXISTS "printed"("path" TEXT NOT NULL, "sha256" TEXT NOT NULL, "at" TEXT NOT NULL, "origin_id" TEXT NOT NULL, UNIQUE("path"));
CREATE TABLE IF NOT EXISTS "changes"("seq" INTEGER PRIMARY KEY AUTOINCREMENT, "table" TEXT NOT NULL, "key" TEXT NOT NULL, "operation" TEXT NOT NULL CHECK(operation IN ('put', 'remove')), "row" TEXT, "at" TEXT NOT NULL, "origin_id" TEXT NOT NULL);
