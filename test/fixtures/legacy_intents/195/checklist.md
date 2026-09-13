# Checklist: Doctor-consistency roadmap - decision and release cut (intent 195)

## In Progress
- [x] Task 1, Step 1-10: Cut and publish the 1.4.0 release (version bump, CHANGELOG, tag, push,
      GitHub release with `--latest`, `npm publish` to `latest`, three-surface verify) - see
      `actions/ACTION_1.md`
- [x] Task 2, Step 1: Re-confirm all nine collected intents (187-194, 196) show
      `disposition: delivered` in their own outcome.md - see `actions/ACTION_2.md`
- [x] Task 2, Step 2: Sync the local install (`npx @zalom/plastic update`) and re-run the
      doctor; confirm `hooks_match_registry` clears from fail to pass while
      `graph_links_projection` and `signals_complete` persist at warn - see `actions/ACTION_2.md`
- [x] Task 2, Step 3: Correct `doctor-consistency.md`'s Batch 4 checkbox for 194 from unchecked
      "- delivering" to checked "- delivered"; append one closing `## Log` entry recording the
      true partial result (1 fail before release cleared by the release itself, 2 warn
      persisting); leave `## Goal` byte-for-byte untouched - see `actions/ACTION_2.md`
- [x] Task 2, Step 4: Write intent 195's real `outcome.md` (replaces the scaffold placeholder):
      nine-intent confirmation, doctor before/after, the two mechanism-level lessons (fix the
      mechanism not the list: 190/189/191/196; verify a stated fix before trusting it:
      189/191/192), the open dealintell item - see `actions/ACTION_2.md`
- [x] Task 2, Step 5: Worktree cleanup for intent 195's own code + paired store worktree
      (merge-then-remove, no-op merge since no code work happened there) - see
      `actions/ACTION_2.md`
- [x] Task 2, Step 6: Complete intent 195 via `scripts/end-intent --disposition delivered`
      (INDEX move to `## Completed`, savepoint `Done` bookend, store commit, lock disarm) - see
      `actions/ACTION_2.md`
- [x] CARRIED FORWARD as a visible open item (the carrying is done; the repair itself is NOT executed and awaits the owner's one-time grant): the dealintell Links repair
      (global 26, dealintell 3b, dealintell 15) touches Completed intents and needs the
      owner's explicit one-time grant under the immutability rule before it can run. Proposal
      is written and held at intent 192's `resources/repair-proposal--dealintell-3b-15.md`
      (drop dealintell 3b's three broken single-dash wikilinks, add the missing frontmatter
      edge `3a.chain += ["15"]`, reproject global 26). Until granted, this item stays open and
      `graph_links_projection` stays at warn. Carried forward visibly here and in outcome.md's
      Follow-ups, never silently merged into the release.

## Completed
(move items here when done)

## Session Log
| Date | Items Completed | Notes |
|------|-----------------|-------|
