-- A node reads several input paths: each path is a row of node_inputs, in the order given, and the column input goes.
-- The input path a node held becomes its first row, so no path is lost.
CREATE TABLE IF NOT EXISTS work."node_inputs"("intent_id" TEXT NOT NULL, "node_id" TEXT NOT NULL, "position" INTEGER NOT NULL, "path" TEXT NOT NULL, "origin_id" TEXT NOT NULL, UNIQUE("intent_id", "node_id", "position", "origin_id"));
INSERT INTO work."node_inputs" ("intent_id", "node_id", "position", "path", "origin_id") SELECT "intent_id", "id", 1, "input", "origin_id" FROM work."nodes" WHERE "input" IS NOT NULL AND "input" <> '';
ALTER TABLE work."nodes" DROP COLUMN "input";
