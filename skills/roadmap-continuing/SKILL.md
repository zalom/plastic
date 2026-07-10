---
name: plastic-roadmap-continuing
description: >-
  Use when the user wants to continue or resume a roadmap, pick up a mid-flight delivery batch,
  asks "where is the roadmap", or wants to resume the wave that was shipping, including an
  indirect ask that never names a roadmap directly (for example "where did that batch of
  tickets land"). This is the roadmap route of plastic-continuing: it finds the tier's
  mid-flight roadmap, presents its state, then asks how to proceed exactly once.
user-invocable: true
---

# Roadmap Continuing - resume the mid-flight roadmap

`plastic-roadmap-continuing` is the roadmap route of `plastic-continuing`. It finds the tier's
mid-flight roadmap, presents its state, then asks the user how to proceed, exactly once.

Before intent 158a1 there was no automated way to do this: the `171` (consistency-dividend)
roadmap handoff had to be resumed by hand, carried as a free-prose note in `171`'s own
`## Insights`. This skill closes that gap.

## Find the mid-flight roadmap

1. Determine the tier (project vs. global) and enumerate that tier's live `roadmaps/*.md`
   (exclude `roadmaps/archived/`). Read via Read/glob, or `plastic-roadmap`'s Read/consume
   verb. See `plastic-roadmap`'s `references/file-format.md` for the file grammar; do not
   duplicate it here.
2. For each candidate, also read its paired ledger `roadmaps/<slug>.savepoint.md` when present
   (see `plastic-roadmap`'s `references/file-format.md#savepoint-ledger`): its last line(s) are a
   cheaper, precise last-event signal (for example `dispatched 134` or `merged 172`), read
   alongside the existing `## Waves`/`## Log` judgment. The ledger is read-only here, a derived
   signal, never a new status field; INDEX.md stays the sole status writer.
3. Rank liveness at read time (no new field is written). See `references/liveness-ranking.md`
   for the full algorithm and the tie rule.
4. A genuine tie (two candidates equally live) is presented to the user and resolved by the
   single ask below, not silently picked.

## Present state

Present the chosen roadmap's `## Goal`, the current wave with each entry's mirrored status, the
ledger's newest line(s) (the last mechanized event) alongside the newest `## Log` line, before any
ask, so the coordinator sees the machine last-event at a glance.

## Ask once

Ask "auto or guided?" exactly once, after presenting state, mirroring
`plastic-intent-starting`'s single-ask contract:
- **guided** -> continue step by step with the user.
- **auto** -> hand off to `plastic-auto` to drive the next wave or entry.

Never re-ask. No new roadmap or INDEX status field is invented anywhere in this flow.

## No new script

The enumeration and ranking above are a read-time judgment done in prose, not a helper script.
A helper script would need its own `core_files` registration and a hermetic test, raising the
packaging surface for no material benefit here - so none is added. `scripts/roadmap-savepoint`
already exists (intent 134, owned by `plastic-roadmap`); this skill only READS the ledger it
writes.

## Caller contract: who writes the ledger

This skill is a reader, not a writer, of `roadmaps/<slug>.savepoint.md`. The coordinator flows
(`plastic-auto`, the enforcer, and this skill's own resume-and-hand-off path) call `ruby
~/.plastic/scripts/roadmap-savepoint append` at their own dispatch, merge, park, handoff, and
release points, the same events `plastic-roadmap`'s verbs append at their closing steps. A
resuming coordinator therefore both reads the ledger here and writes to it as it drives the next
wave or entry.

## References

- `references/liveness-ranking.md` - the read-time ranking algorithm and the tie rule.
