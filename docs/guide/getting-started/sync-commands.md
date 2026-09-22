# Sync commands

Plastic keeps the store files and three SQLite databases level. The files stay the working
copy. The databases hold the same content in a form that commands can query, back up and
restore. The commands need the `sqlite3` command, which macOS ships.

## The three databases

The following table shows each database and what it holds:

| Database | Holds |
| -------- | ----- |
| `~/.plastic/knowledge_graph.db` | Every markdown file in the stores, compressed, with a hash and the search index. |
| `~/.plastic/work_graph.db` | One `intent` row for each `INDEX.md` line, and one `ledger` row for each `savepoint.md` line. |
| `~/.plastic/references.db` | Every other file in the stores, with its intent id and SHA-256 hash. Lock files, `.tmp` files and `.DS_Store` files are left out. |

## Commands

The following table shows each command and what it does:

| Command | What it does |
| ------- | ------------ |
| `plastic sync [--dry-run]` | Brings the files and the databases level. The first run builds the databases. |
| `plastic checkout` | Restores every missing file from the databases, byte for byte. |
| `plastic render FILE` | Prints one markdown file as an HTML page with one stylesheet. |

The `sync` and `checkout` commands take `--json`.

## Sync

For each markdown file, `plastic sync` compares the file, its row and the hash recorded at the
last sync. The following table shows what it does:

| What changed | What sync does |
| ------------ | -------------- |
| The file | Reads the file into its row and rebuilds the search index. |
| The row | Writes the row out to the file. |
| Both | Exits 3, prints each path with a diff, and writes nothing. |

A new file gets a new row. A missing file is written out again from its row. With `--dry-run`,
the command prints the same lines and writes nothing:

```text
$ plastic sync --dry-run
read  projects/plastic/store/368--search-index-in-knowledge-graph-db/spec.md

next: plastic search TERMS
because: a changed file is read into its row, a changed row is written out, and both changed is yours to settle
```

When both sides changed, you decide which side wins. To keep the file, delete the row with
`sqlite3` and sync again. To keep the row, delete the file and sync again.

Each sync rebuilds `work_graph.db` whole, and adds new and changed files to `references.db`.

## Checkout

Run `plastic checkout` after a file is lost. The command restores only files that are missing.
It never overwrites a file that exists, so an edit is safe.

## Render

`plastic render FILE` prints a complete HTML page on standard output. The page keeps every
heading and table, and it carries one inline stylesheet, `templates/render.css`:

```text
$ plastic render spec.md > spec.html
```

## Doctor

`plastic doctor` checks the links between the databases. It warns when files belong to an
intent id that has no row in `work_graph.db`.
