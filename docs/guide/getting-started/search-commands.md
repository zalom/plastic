# Search commands

Plastic keeps a search index of every markdown file in the stores. The index is one SQLite
file, `~/.plastic/knowledge_graph.db`. It holds each file's text in compressed form and a
full-text index over that text. The commands need the `sqlite3` command, which macOS ships.

## Commands

The following table shows each command and what it does:

| Command | What it does |
| ------- | ------------ |
| `plastic index` | Rebuilds the whole index and prints the number of files. |
| `plastic search TERMS [--project SLUG] [--limit N]` | Prints the best matching paths, each with one excerpt. The limit defaults to 10. |
| `plastic query SQL` | Runs one read-only SQL statement on the index and prints the rows. |

Every command takes `--json`.

## Build the index

Run `plastic index` after the stores change. The command builds a new file and then replaces
the old one, so a failed build leaves the old index in place. The index is never updated in
part.

## Search

Each term is read as plain text, so a hyphen or a colon in a term is safe. Put a phrase in
quotation marks to match the words together:

```text
$ plastic search "byte budget" --project plastic --limit 1
projects/plastic/store/372--skills-and-hooks-to-commands/spec.md  ... Each removal lowers the [byte-budget] test's target ...

next: plastic index
because: the index was built 2026-09-21 14:40; rebuild it when the stores have changed
```

The excerpt marks each matched term with brackets. The `because:` line gives the build date,
so you can tell whether the index is older than your last change.

## Query

The index has one table, `doc`, with the columns `id`, `path`, `sz` and `data`. The view
`doc_v` gives the text of each file as `body`. The database is opened read-only, so a
statement that writes fails and changes nothing:

```text
$ plastic query "SELECT count(*) AS docs FROM doc"
1  docs=7956
```
