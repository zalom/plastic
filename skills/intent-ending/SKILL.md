---
name: plastic-intent-ending
description: >
  Wrap, finish, close, or mark an intent Done, delivered or abandoned. The
  single owned Done procedure every exit route (auto mode, the curator path,
  releasing) calls for the mechanical close, so the savepoint Done bookend is
  never skipped. Use when completing or abandoning an intent, when a
  checklist reaches 100 percent and Exec is finished, or when asked to "wrap
  this up".
user-invocable: true
---

# Intent Ending

The one procedure every terminal transition routes through. Auto mode, the
curator path, and releasing all call this skill (or its backing script,
`scripts/end-intent`) for the mechanical close instead of restating the same
prose three times. `abandoned` is the SAME procedure as `delivered`, not a
failure branch: only outcome.md content and the INDEX section differ.

## The 8 steps (0-7)

| # | Step | Who does it |
|---|---|---|
| 0 | Precondition check | You, before touching outcome.md |
| 1 | outcome.md + intent-file `## Outcome` summary | `scripts/end-intent` |
| 2 | INDEX.md terminal move (Active -> Completed/Abandoned) | `scripts/end-intent` |
| 3 | savepoint `Done` bookend | `scripts/end-intent` |
| 4 | store auto-commit | `scripts/end-intent` |
| 5 | disarm (worktree + lock) | You, after end-intent exits 0 |
| 6 | QMD reindex, async, LAST | You |
| 7 | EM-to-CTO report | You |

Steps 1-4 are ONE callable script, not four separate one-liners: this is
exactly what the failure mode this intent fixes looked like (releasing hand
authored the close in prose and dropped the savepoint bookend for two real
deliveries). Never restate outcome/INDEX/savepoint prose inline again; call
`scripts/end-intent`.

### Step 0. Precondition (predict the deny, do not fight it)

`Bridge.check_gate` is LIVE code already wired into the write-time hook. It
BLOCKS an outcome.md write while any non-completion item in checklist.md is
still unchecked (`- [ ]`). This skill's own precondition step only SURFACES
that gate in prose before you hit it:

1. Read checklist.md. Every non-completion item must be checked. The
   orchestrator-owned items (merge, this skill's own close) are the only
   ones allowed to stay open at this point; every actual delivery item must
   be ticked.
2. Confirm every acceptance criterion in spec.md is verifiable (tests pass,
   or the manual check described in its HOW line was actually run).
3. If either check fails, stop here. Finish the checklist or spec gaps
   first; do not attempt outcome.md and fight the gate's deny.

### Step 1-4. Run `scripts/end-intent`

First author outcome.md for real (never leave the scaffold placeholder in
place): copy `templates/outcome.md`, set the frontmatter to
`disposition: delivered` or `disposition: abandoned`, and fill `## Summary`,
`## Delivered`, `## Verification`, `## Follow-ups`. On abandon, `## Summary`
states the abandonment reason and the trail (see Pivot below).

Then call the script once:

```bash
ruby ~/.plastic/scripts/end-intent \
  --store <store_path> --id <intent_id> --disposition delivered|abandoned \
  --outcome-summary "<one-line ## Outcome summary for the intent file>"
```

This does all of steps 1-4 in order: guards outcome.md (refuses a missing,
still-placeholder, or wrong-disposition file with exit 2 and authors
nothing), stamps the intent file's `## Outcome` section, moves the INDEX.md
line from `## Active` to `## Completed` or `## Abandoned` (dated today,
idempotent), appends the savepoint `Done` bookend, and commits the store
repo. Add `--no-commit` when a separate commit step already covers the
store, and `--dry-run` to preview with no writes. Exit 0 is success; exit 1
is a usage or resolution failure; exit 2 is the outcome.md guard refusing
(fix outcome.md and re-run, nothing was written).

### Step 5. Disarm (worktree + lock)

Two branches, decided by how this intent ships:

- **Shipped through a release** (the `plastic-releasing` flow reached this
  close): merge the code branch back BEFORE removing the worktrees, via
  `Worktree.finish(bridge_data, merge: true)`. Releasing's own workflow
  already drives this; this skill's job here is only the outcome/INDEX/
  savepoint/commit core above.
- **Auto mode or the curator path** (no release involved): plain remove,
  branch survives for reclaim.
  ```bash
  ruby -r ~/.plastic/scripts/lib/bridge -e \
    'Bridge.disarm_auto(ENV["CLAUDE_CODE_SESSION_ID"], intent_id: "<ID>")'
  ```
  `disarm_auto` releases both worktrees, clears the `delivery.lock`, and only
  then makes the bridge purge-eligible, in that order. Never leave an
  orphaned worktree; run `git worktree prune` on a stale reference.

### Step 6. QMD reindex, LAST

Only after step 5 has released the worktrees and cleared the lock, so the
index never references state about to disappear:

```bash
ruby ~/.plastic/scripts/qmd-sync reindex --store <store-root> --async
```

No-op when QMD is absent. Runs in the background so it never blocks the
turn.

### Step 7. EM-to-CTO report

Brief the human like an engineering manager to a CTO: impact and risk first,
in plain language, the decision left to them (merge, release, or accept).
See `outcome.md` for the details; do not restate it verbatim.

## Abandoned is the same procedure

`disposition: abandoned` runs the identical steps 0-7. The only differences
are outcome.md content (Summary states why this was abandoned, not what was
delivered) and the INDEX target section (`## Abandoned` instead of
`## Completed`). Never branch the mechanical steps by disposition; the
script already does that internally.

## Mid-flight pivot

When the work that shipped differs from what spec.md or plan.md originally
called for, do not retcon those documents. Record the decision once in
`## Insights`, then let outcome.md carry the truth of what actually
happened, including the abandoned trail when part of the work was dropped
mid-flight. outcome.md is truth of delivery; spec and plan stay the
historical record of what was planned.

## Routing

`plastic-releasing`, `plastic-auto`, the curator agent, `intent-curator`, and
`managing-index` all delegate their mechanical close to this skill (or call
`scripts/end-intent` directly for steps 1-4). None of them restate the
outcome/INDEX/savepoint prose inline any more; if you find one that does,
that surface has drifted and should route here instead.
