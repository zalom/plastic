<!-- provenance header, not part of the ledger this fixture carries -->
# Provenance

Copied verbatim, byte-identical, never edited to fit, from:

- Source store: `/Users/zlatko/.plastic/projects/plastic/store/337--roadmap-graph`
- Copied: 2026-09-11T09:11:21Z
- Files copied: `337--roadmap-graph.md` (the intent record, needed only so
  `scripts/graph-measure`'s directory check recognizes this as an intent directory),
  `savepoint.md`, `nodes/` (10 files). `graph.md` and `packets/` are not part of this
  fixture; the packet lists only `savepoint.md` and `nodes/` for 337.
- `savepoint.md` md5: `64bc169260d18c6ec5aa2e5fa2cc63ea`

This is intent 337's real delivery ledger (the roadmap graph model), used by intent 343's n3
dogfood (matrix rows 3.12-3.20, 3.21-3.23). `savepoint.md` has no `Why` line at all, the real
case D20's clock-anchor fallback exists for. `nodes/r1.md` is the only `kind: research` node
in either fixture; without it, every 337 row would measure the `NodeFile::KIND_PREFIX`
fallback while claiming to measure 337's real node kinds. Never edit the copied files to make
a test pass; if the fixture is wrong, fix the fixture by re-copying from the source, never by
hand-patching a line to fit.
