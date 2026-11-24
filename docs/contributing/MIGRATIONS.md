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

- Each kept table is named for the live table and the version, such as `document_revisions_20261119000000`.
  It is made from the live table's own `CREATE TABLE` text, so it keeps the old shape.
- `LegacyKeep::KEEPS` in `lib/plastic/graph/migration/legacy_keep.rb` lists the versions that
  keep what they remove. `LegacyKeep::WHOLE` lists the tables such a version drops, kept whole
  just before its SQL runs. A data step gets a `keep:` callable and keeps each row before it
  deletes it.
- The store migration attaches `legacy.db` only while a version of `KEEPS` or `TRIMS` is pending,
  or a version of `LegacyPages::VERSIONS` is pending and the file is there, so no other run
  makes the file.
- A backup copies `legacy.db` when the store has one, and a restore puts it back.

A migration whose removed rows a sync up reads back keeps nothing. `LegacyKeep::ALONE` lists
such versions, and a down of one removes its version alone. Migration `20261119180000` drops the
rows of every report that `reports.mandatory` does not name and is in `ALONE`: the files stay on
disk, and a report recorded later gets its rows back on the next sync up.

A migration can also trim what an earlier migration kept. `LegacyKeep::TRIMS` lists such
versions. Migration `20261119190000` trims what `20261119000000` kept to what a down needs: the
earlier texts of the paths the sync reads. It drops each kept `sqlar` row, since each one has a
verified copy on disk or in an archive, and each kept revision that a down rebuilds from the
current documents or that no sync reads. Every store then holds the same legacy rows, whichever
release ran the drop. It is in `ALONE` too: its down removes the version alone, and a down of
`20261119000000` after it puts the trimmed keep back.

A trim leaves the pages it freed in `legacy.db`. `LegacyPages::VERSIONS` lists the versions
that give the free pages of an existing `legacy.db` back to the disk, in the transaction of the
migration. Migration `20261120090000` does this after the trim, so a store that ran the trim
in an earlier release ends the same as one that runs both in one run. A store with no
`legacy.db` gets none. It is in `ALONE`: its down removes the version alone.

To add a migration that removes data, add its version to `KEEPS`, list the tables it drops in
`WHOLE`, and make its data step call `keep` before each delete. Then write the test of its down.

A migration can also rewrite values in place. `LegacyKeep::VALUES` lists such versions. It
keeps the old text of each value it changes in one table named for the version, such as
`changed_values_20261121090000`, with the schema, table and column of the value, the key of its
row, its old text and its new text. The key is a JSON array of the columns of the first full
unique index of the table, which `RowKey` in `lib/plastic/graph/migration/row_key.rb` builds.
Its data step calls `keep.values` before each `UPDATE`.

- `LegacyValues` in `lib/plastic/graph/migration/legacy_values.rb` makes the table only when a
  value changed. A run that made `legacy.db` and kept nothing in it removes the file.
- A down writes each old text back on its own row, where the live value still equals its new
  text. The values the migration changed come back byte for byte, and a value written after the
  migration stays.
- A version of `VALUES` that changed no value has no table, so its down removes the version
  alone.

Migration `20261121090000` writes every stored time that carries an offset in UTC, with `Z`, the
form `Plastic.timestamp` writes. `UtcTimes::COLUMNS` in `lib/plastic/graph/migration/utc_times.rb`
lists the time columns of the store. A date with no time, a time already in UTC and a blank stay
as they are. A time with an offset that names no real moment, such as hour 25, stays as it is
too, and the migrate notes name each one by its column and its text, so a person can fix it. The
migration is in `KEEPS` and `VALUES` and keeps each old text in `changed_values_20261121090000`.

The home migration of the same version does the same for `plastic.db` and names its unreadable
times too. `plastic.db` has no down. The way back is the copy that the home migration writes to
`backups/plastic-<UTC timestamp>.db` before it runs.

After `plastic update`, run `plastic sync down` so the printed files carry the UTC times too. A
sync up reads each time in the files into UTC, so a file an earlier release printed with an
offset still gives UTC rows.

Migration `20261123120000` turns the roadmaps into needs links and drops the five roadmap tables
of `work_graph.db`. Its data step, `RoadmapNeeds` in `lib/plastic/graph/migration/roadmap_needs.rb`,
reads the roadmap edges that `legacy.db` kept and writes one `needs` link from the intent of the
later item to the intent of the earlier one. An edge is skipped, and counted in the migrate notes,
when an item has no intent, when both items belong to one intent, or when the link would close a
loop. The migration is in `KEEPS` and keeps the five tables whole as `<table>_20261123120000`. It
has no switch. Its down, `RoadmapNeedsLinks`, removes every `needs` link and puts the five tables
back from `legacy.db`. A store that never had the tables keeps nothing, and its down removes the
version alone.

Migration `20261124090000` drops the five roadmap tables of `work_graph.db` again. Migration
`20261123120000` had dropped them, but on the `plastic` store of one machine they came back, all empty.
Since commit 804fa952 (16 November 2026) every open of a store is gated: `SchemaGate` refuses a store whose
ledger holds a version the code does not know. Every release from 3.0.0-beta.1 and every checkout from
that commit on therefore cannot open the migrated store and make a table. The tables came from a checkout
from before the gate, local `alpha` at fdb2b9d3 of 13 November 2026, which opened the store with no gate
and made each table that its `schema.rb` declared and the store lacked. No release and no gated code
declares or makes them: only the down of migration `20261123120000` makes them, from `legacy.db`. A
migration that is already recorded never runs again, so the drop needs a new version. It has no switch. It is
in `KEEPS`, and `RoadmapTables::VERSION` marks it as keeping a table only when it holds a row: a table that
holds a row is kept whole in `legacy.db` as `<table>_20261124090000` before the drop, an empty table is kept
nowhere, and a store with none of the tables only records the version. Its down, `RoadmapTables` in
`REBUILDS`, builds the five tables again, empty and with the text of the live tables (UNIQUE keys, and the
batch and position of an item NOT NULL), and puts back each row that the migration kept. A store that never
had the tables gets them empty from the down too. Opening a store with that old checkout again makes the
tables again, and no later migration drops them, because the version is recorded and never runs again. The stop is
to bring that checkout past commit 804fa952.

## Hold a migration behind a switch

A migration that changes stored data ships behind a config switch that is off by default, as
`docs/release-lines.md` says, with one exception: the UTC migration named at the end of this
section. `MigrationList::HELD` in
`lib/plastic/graph/schema/migration_list.rb` maps each held version to its switch. Migration
`20261119000000`, its trim `20261119190000` and the page migration `20261120090000` are held
behind `migrate.drop_document_revisions`, so the three run in the same `plastic update`.

- While the switch is off, a run leaves the held version out of the pending ones. A store that
  lacks only that version is current, so every command opens it and `plastic update` leaves it.
- A store that records a held version is current too. A new store records every version, held
  or not, because it is built from `schema.rb`.
- Once the switch is on, `plastic update` runs the held version as it runs any other. The runner
  takes the released versions from `Wiring::Settings#released`.

To hold a new migration, add its version and its switch to `HELD`, and add the switch to
`lib/plastic/config/defaults.rb`, off.

Two migrations are exceptions to this rule. Migration `20261121090000`, which writes every stored
time in UTC, has no switch: the owner ruled on 22 November 2026 that it changes the text of a time
and not the time it names, and the code that reads times expects UTC. Migration `20261123100000`,
which drops the node columns `judge` and `verdict`, has no switch either: Jev chose that on
23 November 2026 (ruling D1 of intent 488), following the owner's ruling for intent 498.

Migration `20261123100000` drops the columns `judge` and `verdict` of `nodes` in `work_graph.db`.
No code read or wrote them, and the nodes of all 15 real stores held no value in either. It has no
switch, as the owner ruled on 22 November 2026 for the roadmap migration of intent 498: a held
migration would leave some stores on a layout with the columns and others without. A store keeps
nothing of it in `legacy.db`, and the backup that every migration run takes first holds the
columns. It is in `ALONE`, and its down, `NodeJudgeColumns` in `REBUILDS`, adds both columns
back, empty. A graph file that an earlier release printed with the two fields still reads: the
sync reads past them.

Migration `20261123154000` adds the nullable column `deadline` to `nodes` in `work_graph.db`, the
minutes a claim on a node may run before `plastic graph ready` reports it as overdue. It writes no
value, so it has no switch, and a node it finds keeps no deadline. It is in `ALONE`, and its down,
`NodeDeadlineColumn` in `REBUILDS`, drops the column again; the backup that the down takes first holds
any deadline a node had.

Migration `20261123170000` lets a node read several input paths. It creates the table `node_inputs` in
`work_graph.db`, one row for each path with its `position`, copies each stored `nodes.input` as
position 1, and drops the column. It is in `ALONE`, and its down, `NodeInputsColumn` in `REBUILDS`,
adds the column back, fills it from position 1 and drops the table; a node with more than one path
keeps only the first, and the backup that the down takes first holds the rest. A graph file that an
earlier release printed with `input` on a node still reads: the sync reads it as a row at position 1.

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
| `plastic migration down --store SLUG` | Backs the store up, puts the rows the newest migration the store records kept back into the live tables in their old shape, drops them from `legacy.db`, removes the version from the store and adds a `down` row to the ledger. It offers `plastic migration list --store SLUG`. |
| `plastic migration purge VERSION --store SLUG` | Takes a backup of the store when the newest is older than 12 hours, as other commands that can lose data do. Then it removes the rows one migration kept from `legacy.db`, gives their space back to the disk and adds a `purge` row to the ledger. After it, a down cannot undo that migration. |

A down refuses with exit 3 and changes nothing in these cases:

- The store records a version newer than this release, or lacks one older than the newest it records.
- The newest migration kept nothing and is not in `LegacyKeep::ALONE`.
- The rows it kept are not in `legacy.db`. A version of `VALUES` with no table is not refused:
  it changed no value, so its down removes the version alone.
- A live row it would overwrite changed after the migration kept it.

A failed backup stops the down with exit 1 before it changes anything. After a down, the store
has the layout of the release before the migration, and `plastic update` migrates it up again.
In the same transaction, the down of migration `20261119000000` builds a `document_revisions` row
for each current document that has none, from `documents` and `document_heads`. The release
before it then finds every document in its search, its reads by revision and its integrity audit.
A migration that needs such rows on its down adds its version to `MigrationDown::REBUILDS`.
A down undoes only the newest migration the store records. A second down then undoes the one
before it. To go back past a migration that kept nothing, restore a backup.

A down undoes one store, not the install. `plastic.db` and the other stores keep their
versions, so an older release still refuses them, and the down never offers `plastic rollback`.

A purge of a version that keeps no rows of the store is a usage error, exit 2.
