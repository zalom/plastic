-- A run keeps its harness, its worker session, a note on what the harness record lacked, its model, its token counts and its cost.
ALTER TABLE work."runs" ADD COLUMN "harness" TEXT NOT NULL DEFAULT '';
ALTER TABLE work."runs" ADD COLUMN "worker_session" TEXT NOT NULL DEFAULT '';
ALTER TABLE work."runs" ADD COLUMN "usage_note" TEXT NOT NULL DEFAULT '';
ALTER TABLE work."runs" ADD COLUMN "model" TEXT;
ALTER TABLE work."runs" ADD COLUMN "input_tokens" INTEGER;
ALTER TABLE work."runs" ADD COLUMN "output_tokens" INTEGER;
ALTER TABLE work."runs" ADD COLUMN "cache_read_tokens" INTEGER;
ALTER TABLE work."runs" ADD COLUMN "cache_write_tokens" INTEGER;
ALTER TABLE work."runs" ADD COLUMN "cost_usd" REAL;
