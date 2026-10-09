# Backup command

`plastic backup` copies the databases of one store into a folder on your machine.
Plastic sends nothing anywhere. Copying the folder off the machine is your choice.

## Commands

Every command needs `--store SLUG`, the name of a store in `~/.plastic/projects.yml`.
The following table shows each command and what it does:

| Command | What it does |
| ------- | ------------ |
| `plastic backup --store SLUG [--databases LIST] [--live] [--dry-run]` | Copies the databases into `~/.plastic/stores/SLUG/backups/YYYYMMDDHHMMSS/`. |
| `plastic backup list --store SLUG` | Prints the number, the folder, the start time, the status and the goal of each backup. |
| `plastic backup purge --store SLUG (--older-than DATE \| --all \| --failed) [--dry-run]` | Deletes the backups before a date, all of them, or those that failed. |
| `plastic backup restore --store SLUG (--timestamp TS \| --latest) [--databases LIST] [--dry-run]` | Puts a backup back. |

All commands take `--json`. `LIST` is a comma list of `work_graph`, `knowledge_graph` and
`references`. Leave `--databases` out for all three.

## What a backup holds

The folder name is the UTC time of the backup. The following table shows its entries:

| Entry | Holds |
| ----- | ----- |
| `work_graph-TS.db`, `knowledge_graph-TS.db`, `references-TS.db` | A consistent copy of each database, taken while other commands may still write. |
| `backup.log` | One line for each database copied and a last line for the result, each with a UTC time. `--live` prints the lines as they are written. Restore and list ignore it. |
| `status.yml` | `status:` is `in-progress`, `done` or `failed`. `goal:` is `full` or `partial:` and the file names. |

`backup list` shows the start time in your time zone. It exits 1 when a backup with a row
is missing or changed.

## Purge

`--older-than` takes a date, read as local midnight, or a full time with an offset. It
deletes the backups made strictly before it. `--failed` deletes every backup whose status
is `failed`, and never one that is `in-progress` or `done`. Give exactly one of `--older-than`,
`--all` and `--failed`. Add `--dry-run` to see which ones.

## Restore

`plastic backup restore` only restores a backup whose status is `done`. `--latest` picks
the newest one. It refuses while a delivery lock is fresh. Before it changes anything it
backs up the current databases, so the restore can be undone with a second restore.

A restore never syncs by itself, and it asks no question, at a terminal or without one. It replaces
the databases and ends with `next: plastic sync down --project STORE`. Run that line to write the
files from the restored rows; file edits made after the backup are lost. To keep a file that is newer
than the backup, run `plastic sync up --project STORE` instead.
