-- The ledger of store migrations: one row for each up, down or purge of a migration on a store.
CREATE TABLE IF NOT EXISTS "store_migrations"("id" INTEGER PRIMARY KEY AUTOINCREMENT, "store" TEXT NOT NULL, "version" TEXT NOT NULL, "event" TEXT NOT NULL CHECK(event IN ('up', 'down', 'purge')), "at" TEXT NOT NULL, "moved" TEXT NOT NULL, "undoable" INTEGER);
