# Tracking

Plastic tracks work on your machine, in files you own. It collects no usage data.

| Record | Place | Written when |
| ------ | ----- | ------------ |
| Install ledger | `~/.plastic/versions.json`, one JSON object per line | Install, update, rollback, reinstall |
| Work log lines | The `work_log` table of the store's `work_graph.db`, printed to `work.log` in each intent folder | Each intent, node, edge and archive write, and when a hand-written line reaches the rows through `plastic sync up`. The kinds are `opened`, `approved`, `parked`, `ruled`, `verdict`, `wrote`, `noted`, `added`, `removed`, `claimed`, `capped`, `released`, `done`, `failed`, `asked`, `impeded`, `resolved`, `edge_added`, `edge_removed`, `archived`, `unarchived`, `abandoned` and `amended`, the line of each link that `plastic resources sort` rewrites in a core file of a done or abandoned intent. A write stores its rows and its `work_log` line in one transaction, so a cut-short write leaves neither. |
| Roadmap log | The roadmap's rows, printed to `roadmaps/<slug>.md` in the store | Each `plastic roadmap log` |
| Sessions | The `sessions` table of `~/.plastic/plastic.db` | Each session start, turn end and session end |

The `plastic` command reads these records and writes them too: the installer commands write the
install ledger, `plastic intent new` writes an intent's first work log line, `plastic roadmap
log` appends to a roadmap's log, and the session hooks and `plastic session note` write the
session rows.

## Standing context

Plastic measures the text it adds to every agent session. `test/standing_surface_test.rb`
sums the standing surface in bytes, and the test fails when the sum crosses its 5,000-byte
cap. The cap only moves down.
