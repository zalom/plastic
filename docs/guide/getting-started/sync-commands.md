# Sync commands

Each store keeps its content as rows in three SQLite databases, and prints the files of its
folder from those rows. A file you change by hand reaches its rows through `plastic sync up`.
A row that changed reaches its file through `plastic sync down`.

## The three databases

The following table shows each database of a store and what it holds. Each one lives in the
store's folder, `~/.plastic/stores/SLUG/`:

| Database | Holds |
| -------- | ----- |
| `work_graph.db` | The intents, their nodes and edges, the savepoints, the roadmaps, and a record of each printed file. |
| `knowledge_graph.db` | Every document of the store with its revisions, and the search index. |
| `references.db` | Every other file of the store, as an archive. |

## Commands

The following table shows each command and what it does:

| Command | What it does |
| ------- | ------------ |
| `plastic sync up [--overwrite [PATH]] [--merge] [--dry-run]` | Reads the files changed by hand into rows. |
| `plastic sync down [--overwrite [PATH]] [--merge] [--dry-run]` | Writes the rows that changed into files. |

A record that changed on both sides since the last print, in its file and in its rows, is a
conflict. A plain call with a conflict writes nothing, exits 3 and lists every conflict. The
options settle it:

| Option | Effect |
| ------ | ------ |
| `--overwrite [PATH]` | Settles conflicts on the side the command reads from: `sync up` keeps the file, and `sync down` keeps the rows. With `PATH` it settles that one record, and without it every conflict. |
| `--merge` | Applies the changes made on one side only, then lists the conflicts and exits 3. |
| `--dry-run` | Runs the whole sync in a disposable copy and changes nothing. |
