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
2. Rank liveness at read time (no new field is written; INDEX.md stays the sole status
   writer). See `references/liveness-ranking.md` for the full algorithm and the tie rule.
3. A genuine tie (two candidates equally live) is presented to the user and resolved by the
   single ask below, not silently picked.

## Present state

Present the chosen roadmap's `## Goal`, the current wave with each entry's mirrored status,
and the newest `## Log` line(s), before any ask.

## Ask once

Ask "auto or guided?" exactly once, after presenting state, mirroring
`plastic-intent-starting`'s single-ask contract:
- **guided** -> continue step by step with the user.
- **auto** -> hand off to `plastic-auto` to drive the next wave or entry.

Never re-ask. No new roadmap or INDEX status field is invented anywhere in this flow.

## No new script

The enumeration and ranking above are a read-time judgment done in prose, not a helper script.
A helper script would need its own `core_files` registration and a hermetic test, raising the
packaging surface for no material benefit here - so none is added.

## References

- `references/liveness-ranking.md` - the read-time ranking algorithm and the tie rule.
