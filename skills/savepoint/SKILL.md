---
name: plastic-savepoint
description: Use when verifying or repairing an intent's savepoint ledger, when the user says "save" or "savepoint", or when a PreCompact hook fires. The ledger is written automatically by the gate hook at each lifecycle boundary; this skill only reads, verifies, and rebuilds it.
user-invocable: false
---

# Savepoint

`savepoint.md` is a deterministic, append-only ledger of an intent's cycle steps, one line
per lifecycle milestone, newest at the bottom:

```
2026-06-16T14:02Z  What  34--cycle-step-savepoints.md
2026-06-16T14:20Z  Why   spec.md created
2026-06-16T15:10Z  How   plan.md created
2026-06-16T15:11Z  How   checklist.md created
2026-06-16T16:40Z  Exec  outcome.md created
```

It is **sugar on top of the conventions**, not a source of truth. The gate hook
(`hook-gate-check`) writes each line automatically when a stage file is created, so there is
nothing to save by hand. State is always derivable from files-on-disk; the ledger just lets
a resuming agent read the cycle's succession from one glance (last line = where we are).

## When to Use
- A PreCompact hook fires, or the user says "save" / "savepoint": verify the ledger is current.
- Resuming an intent: read the ledger to learn the cycle's succession quickly.
- The ledger looks stale, empty, or missing: rebuild it from the filesystem.

## What this skill does NOT do
- It does not write prose, "in progress", "next step", or "blockers". The old 50%-context
  prose savepoint is retired. The semantic trace lives in `## Insights` (append-only,
  newest at the bottom); the byte history lives in git.

## Workflow

### 1. Find Active Intent(s)
Read the active store's `INDEX.md` and extract intents under `## Active`.

### 2. For Each Active Intent — verify the ledger
- Read `savepoint.md`. Confirm it exists and is non-empty.
- Confirm the **last line's stage** matches the stage derived from files-on-disk
  (`Bridge.derive_stage`). If they disagree, or the file is missing/empty, the ledger has
  drifted.

### 3. Rebuild on drift
Reconstruct from the filesystem rather than hand-editing:

```bash
ruby -r ~/.plastic/scripts/lib/bridge -e \
  'Bridge.rebuild_savepoint("<intent_dir>")'
```

This rewrites `savepoint.md` from the milestone files present (timestamps from mtimes),
in stage order. Safe to run anytime: the ledger is derived.

### 4. Commit (store only)
If a rebuild changed the ledger, commit it in the store repo:
```bash
cd <store-root> && git add . && git commit -m "chore: rebuild savepoint ledger — [intent]"
```
Never push `~/.plastic/`.

## References

- Read `references/context-management.md` for the full save/continue protocol and how the
  resume flow consumes the ledger.
