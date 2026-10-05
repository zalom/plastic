# Backup command

`plastic backup` copies the databases of one store into a folder on your machine.
Plastic sends nothing anywhere. Copying the folder off the machine is your choice.

## Commands

Every command needs `--store SLUG`, the name of a store in `~/.plastic/projects.yml`.
The following table shows each command and what it does:

| Command | What it does |
| ------- | ------------ |
| `plastic backup --store SLUG [--databases LIST] [--dry-run]` | Copies the databases into `~/.plastic/stores/SLUG/backups/YYYYMMDDHHMMSS/`. |
| `plastic backup list --store SLUG` | Prints the number, the folder, the start time, the status and the goal of each backup. |
| `plastic backup purge --store SLUG (--older-than DATE \| --all) [--dry-run]` | Deletes the backups before a date, or all of them. |
| `plastic backup restore --store SLUG (--timestamp TS \| --latest) [--databases LIST] [--dry-run]` | Puts a backup back. |

All commands take `--json`. `LIST` is a comma list of `work_graph`, `knowledge_graph` and
`references`. Leave `--databases` out for all three.

## What a backup holds

The folder name is the UTC time of the backup. The following table shows its entries:

| Entry | Holds |
| ----- | ----- |
| `work_graph-TS.db`, `knowledge_graph-TS.db`, `references-TS.db` | A consistent copy of each database, taken while other commands may still write. |
| `status.yml` | `status:` is `in-progress`, `done` or `error`. `goal:` is `full` or `partial:` and the file names. |

`backup list` shows the start time in your time zone. It exits 1 when a backup with a row
is missing or changed.

## Purge

`--older-than` takes a date, read as local midnight, or a full time with an offset. It
deletes the backups made strictly before it. Add `--dry-run` to see which ones.

## Restore

`plastic backup restore` only restores a backup whose status is `done`. `--latest` picks
the newest one. It refuses while a delivery lock is fresh. Before it changes anything it
backs up the current databases, so the restore can be undone with a second restore.

A restore never syncs by itself. At a terminal it asks you to choose:

- `down` prints the files from the restored rows. File edits made after the backup are lost.
- `up` reads the files into the rows. Where a file is newer, it replaces the restored row.
- `neither` changes nothing; the rows and the files stay as they are.

When no terminal is there, such as when an agent runs it, the restore asks nothing. Its
`next:` line tells the agent to ask you which one you want.
