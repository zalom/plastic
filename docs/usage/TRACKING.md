# Tracking

Plastic tracks work on your machine, in files you own. It collects no usage data.

| Record | Place | Written when |
| ------ | ----- | ------------ |
| Install ledger | `~/.plastic/versions.json`, one JSON object per line | Install, update, rollback, reinstall |
| Intent ledger | `savepoint.md` in each intent directory | Each stage event of an intent |
| Roadmap ledger | `roadmaps/<slug>.savepoint.md` | Dispatch, merge, park and hand-off of a batch |
| Day ledger | `.sessions/<day>/` in the global store: `~/.plastic/stores/global/store/.sessions/<day>/`, or `~/.plastic/store/.sessions/<day>/` in a home not yet moved | During each session |

The `plastic` command reads these records and writes them too: the installer commands write the
install ledger, `plastic intent note` appends to an intent's `savepoint.md`, `plastic roadmap
log` appends to a roadmap ledger, and `plastic session handoff` writes into the day ledger.

## Standing context

Plastic measures the text it adds to every agent session. `bin/plastic-bench` measures each
standing surface in bytes, and a test fails when a surface crosses its ceiling. A ceiling
only moves down.
