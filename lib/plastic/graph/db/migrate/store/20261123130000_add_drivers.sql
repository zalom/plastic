-- The driver claim of an intent: one row for the session that drives it, renewed like a node claim.
CREATE TABLE IF NOT EXISTS work."drivers"("intent_id" TEXT NOT NULL, "origin_id" TEXT NOT NULL, "session_id" TEXT NOT NULL, "claimed_at" TEXT, "seen_at" TEXT, UNIQUE("intent_id", "origin_id"));
