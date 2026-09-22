<!-- provenance header, not part of the ledger this fixture carries -->
# Provenance

Copied verbatim, byte-identical, never edited to fit, from:

- Source store: `/Users/zlatko/.plastic/projects/plastic/store/340--runner-core-in-session`
- Copied: 2026-09-11T09:11:21Z
- Files copied: `340--runner-core-in-session.md` (the intent record, needed only so
  `scripts/graph-measure`'s directory check recognizes this as an intent directory),
  `savepoint.md`, `graph.md`, `nodes/` (14 files), `packets/` (16 files, 448K).
- `savepoint.md` md5: `54ee907a40c5cbd720328992bbea2712`

This is intent 340's real delivery ledger (G7 of the graph-ready plan), used by intent 343's
n3 dogfood (matrix rows 3.1-3.11, 3.21-3.24) and by n4's budget rows, which need `packets/` to
exist (327 D25's hop cap, 224's thirty-delivery kill criterion) alongside `savepoint.md`'s
`packet=` and `hop=` fields. Never edit the copied files to make a test pass; if the fixture is
wrong, fix the fixture by re-copying from the source, never by hand-patching a line to fit.
