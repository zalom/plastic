# Migrations

A migration changes the layout of a database on every machine that runs Plastic. Plastic
migrates the way Rails does: each migration is a timestamped SQL file, each database records
the migrations it has applied, and a migration runs once.

## Where migrations live

| Folder | Database |
| ------ | -------- |
| `lib/plastic/graph/db/migrate/home/` | `plastic.db`, one on each machine |
| `lib/plastic/graph/db/migrate/store/` | The files of a store, `knowledge_graph.db`, `work_graph.db` and `retrieval_graph.db`, which share one connection |

Each file is named `YYYYMMDDHHMMSS_snake_name.sql`, with the time in UTC. The 14 digits are the
version. A home and a store keep separate tables, so a home migration and a store migration may
share a version.

Each database records its applied versions in this table, which the migrator creates:

```sql
CREATE TABLE IF NOT EXISTS schema_migrations (version TEXT PRIMARY KEY);
```

`plastic.db` holds the table of the home, and `knowledge_graph.db` holds the table of its store.

## Add a migration

1. Name the file by the current UTC time, for example
   `lib/plastic/graph/db/migrate/store/20270105093000_add_node_owner.sql`. The version must sort
   after every migration of its kind on `alpha`.
2. Write the SQL. A store migration names the attached file of each table: `main` is
   `knowledge_graph.db`, `work` is `work_graph.db` and `retrieval` is `retrieval_graph.db`. Do
   not write `BEGIN` or `COMMIT`: the migrator runs the whole run in one transaction.
3. Change `lib/plastic/graph/db/schema.rb` to the layout after the migration, and set its
   `version:` to the new version. A fresh database is built from this file and runs no
   migration, so the file must equal the result of every migration.
4. Write the test first: migrate a file at the earlier layout and compare it with a fresh build.
   The layout comparisons in `test/plastic/graph/migration/store_migration_test.rb` and
   `test/plastic/graph/migration/home_migration_test.rb` already run every migration.
5. Run the gate, `bundle exec ruby bin/verify-change origin/alpha`.

The SQL need not run twice, because SQLite has no `ADD COLUMN IF NOT EXISTS`. The run is what
is idempotent: a migration and its row commit together, so a second run finds the row and
skips the migration.

## Rules the gate enforces

The gate runs `bin/lib/migration_guard.rb` against the tip of the base branch, and fails in two
cases:

- A migration that is on the base branch was changed, renamed or deleted. It has already run on
  real machines, so add a new migration instead.
- An added migration does not sort after the newest migration of its kind on the base branch.
  A database that recorded the newer one would never run it. Give the file a later time.

The base is the tip of the branch, not the merge base. A branch cut before a later migration
merged would pass against its merge base.

## What a run does

1. The migrator reads the state of the database. A current database is left alone. A database
   that records a version this code does not know is refused, and the command exits 3.
2. It takes the write lock and reads the state again. A runner that waited finds the work done.
3. It runs each pending migration in ascending order and inserts its row, all in one
   transaction. A failure rolls back the whole run.

A database from before this scheme has no `schema_migrations` table. A `user_version` of 0 with
tables is the beta.2 layout, which the store and home baselines migrate. A `user_version` of 1
is an alpha build that already has the baseline layout, so it gets the baseline row and no SQL
runs. Any other `user_version` counts as newer than this code.

There are no down migrations. Restore a backup to go back.
