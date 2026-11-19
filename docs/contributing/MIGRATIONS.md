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

The gate runs `bin/lib/migration_guard.rb` against the tip of the base branch, and fails in four
cases:

- A migration that is on the base branch was changed, renamed or deleted. It has already run on
  real machines, so add a new migration instead.
- A migration on the tip of the base branch is missing from the branch and from its merge base.
  It was merged after the branch was cut, so rebase the branch onto the base.
- An added migration does not sort after the newest migration of its kind on the base branch.
  A database that recorded the newer one would never run it. Give the file a later time.
- Two added migrations of one kind share a version. Give one a later time.

The order rule compares with the tip of the branch, not the merge base. A branch cut before a
later migration merged would pass against its merge base.

The guard runs only in the gate. `test/graph_migrations_folder_test.rb` checks the files of the
folder as they are: each file name, each kind folder, and one migration for each version of a
kind. It does not run the guard.

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

## Keep what a migration removes

A migration that removes data keeps it first in `legacy.db`, a fourth file in the store folder.
The keep runs in the transaction of the migration, so the rows stay kept only when the migration
commits.

- Each kept table is named for the live table and the version, such as `sqlar_20261119000000`.
  It is made from the live table's own `CREATE TABLE` text, so it keeps the old shape.
- `LegacyKeep::KEEPS` in `lib/plastic/graph/migration/legacy_keep.rb` lists the versions that
  keep what they remove. `LegacyKeep::WHOLE` lists the tables such a version drops, kept whole
  just before its SQL runs. A data step gets a `keep:` callable and keeps each row before it
  deletes it.
- The store migration attaches `legacy.db` only while a version of `KEEPS` is pending, so no
  other run makes the file.
- A backup copies `legacy.db` when the store has one, and a restore puts it back.

To add a migration that removes data, add its version to `KEEPS`, list the tables it drops in
`WHOLE`, and make its data step call `keep` before each delete. Then write the test of its down.

## The ledger

The `store_migrations` table of `plastic.db` is the ledger. It holds one row for each up, down
or purge of a migration on a store, with the time, the rows the event moved into or out of
`legacy.db` by table, and whether a down can undo it. The store's own `schema_migrations` table
stays the truth of its version. When `plastic.db` stays behind, the stores still migrate, and
one note says that the ledger does not record them.

The ledger row is written after the store change commits. When that write fails, the change
stays and the command exits 0. A down or a purge prints one line on standard error that names
what it did and the row the ledger lacks. The note of a migration names the stores whose rows
it wrote and the stores whose rows the ledger lacks. The up rows of one store are written in one
transaction, so the ledger holds all of them or none.

## Undo the newest migration

| Command | What it does |
| ------- | ------------ |
| `plastic migration list --store SLUG` | Prints the newest version the store records, the rows its `legacy.db` holds, its ledger rows and what a down would undo now. The store answers for itself, and the ledger rows are its history. It changes nothing and offers no next command. |
| `plastic migration down --store SLUG` | Backs the store up, puts the rows the newest migration kept back into the live tables in their old shape, drops them from `legacy.db`, removes the version from the store and adds a `down` row to the ledger. It offers `plastic migration list --store SLUG`. |
| `plastic migration purge VERSION --store SLUG` | Removes the rows one migration kept from `legacy.db`, gives their space back to the disk and adds a `purge` row to the ledger. After it, a down cannot undo that migration. |

A down refuses with exit 3 and changes nothing in these cases:

- The store is behind or ahead of this release.
- The newest migration kept nothing.
- The rows it kept are not in `legacy.db`.
- A live row it would overwrite changed after the migration kept it.

A failed backup stops the down with exit 1 before it changes anything. After a down, the store
has the layout of the release before the migration, and `plastic update` migrates it up again.
In the same transaction, the down of migration `20261119000000` builds a `document_revisions` row
for each current document that has none, from `documents` and `document_heads`. The release
before it then finds every document in its search, its reads by revision and its integrity audit.
A migration that needs such rows on its down adds its version to `MigrationDown::REBUILDS`.
A down undoes only the newest store migration. To go back further, restore a backup.

A down undoes one store, not the install. `plastic.db` and the other stores keep their
versions, so an older release still refuses them, and the down never offers `plastic rollback`.

A purge of a version that keeps no rows of the store is a usage error, exit 2.
