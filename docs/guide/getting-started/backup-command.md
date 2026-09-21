# Backup command

`plastic backup` writes one archive that holds everything Plastic needs to rebuild your stores.
Plastic sends nothing anywhere. Copying the archive off the machine is your choice.

## Commands

The following table shows each command and what it does:

| Command | What it does |
| ------- | ------------ |
| `plastic backup` | Writes one archive under `~/.plastic/backups/`. |
| `plastic backup --list` | Prints the name, the size and the date of each archive. |

Both commands take `--json`. Run `plastic sync` first, because the backup copies the three
databases and exits 1 when one is missing.

## What the archive holds

The archive is named `plastic-backup--YYYYMMDDTHHMMSSZ.tar.gz`, with the time in UTC. The
following table shows its entries:

| Entry | Holds |
| ----- | ----- |
| `knowledge_graph.db`, `work_graph.db`, `references.db` | A consistent copy of each database, taken while other commands may still write. |
| `config.yml`, `projects.yml`, `INDEX.md` | The files at the top of `~/.plastic`, when they exist. |
| `manifest.json` | The Plastic version, the time, and the size and SHA-256 hash of every other entry. |

Plastic writes the archive under a draft name and renames it at the end, so a failed run
leaves no archive behind.

## Restore

To restore, follow these steps:

1. Unpack the archive into an empty `~/.plastic`:

   ```text
   $ mkdir ~/.plastic && tar -xzf plastic-backup--20260921T130233Z.tar.gz -C ~/.plastic
   ```

1. Restore the files from the databases:

   ```text
   $ plastic checkout
   ```

The restore brings back every markdown file and every other file in the stores, byte for
byte. It does not bring back lock files, files under `.tmp`, `.DS_Store` files, empty
directories or the `.git` directories. Keep your own copy of a store's git history when you
need it.
