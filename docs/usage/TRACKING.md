# Tracking

Plastic tracks work on your machine, in files you own. It collects no usage data.

| Record | Place | Written when |
| ------ | ----- | ------------ |
| Install ledger | `~/.plastic/versions.json`, one JSON object per line | Install, update, rollback, reinstall |
| Savepoint lines | The `savepoints` table of the store's `work_graph.db`, printed to `savepoint.md` in each intent folder | When the intent is created, and when a hand-written line reaches the rows through `plastic sync up` |
| Roadmap log | The roadmap's rows, printed to `roadmaps/<slug>.md` in the store | Each `plastic roadmap log` |
| Sessions | The `sessions` table of `~/.plastic/local.db` | Each session start, turn end and session end |

The `plastic` command reads these records and writes them too: the installer commands write the
install ledger, `plastic intent new` writes an intent's first savepoint line, `plastic roadmap
log` appends to a roadmap's log, and the session hooks and `plastic session note` write the
session rows.

## Standing context

Plastic measures the text it adds to every agent session. `bin/plastic-bench` measures each
standing surface in bytes, and a test fails when a surface crosses its ceiling. A ceiling
only moves down.
