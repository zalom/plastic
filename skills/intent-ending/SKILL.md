---
name: plastic-intent-ending
description: >
  Wrap, finish, close, or mark an intent Done, delivered or abandoned. Use
  when completing or abandoning an intent, when a checklist reaches 100
  percent and Exec is finished, or when asked to "wrap this up".
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
| 5 | disarm (worktree + lock) | `scripts/end-intent` (intent 188) |
| 6 | QMD reindex, async, LAST | You |
| 7 | EM-to-CTO report | You |

Steps 1-5 are ONE callable script call, not several separate one-liners: this
is exactly what the failure mode this intent fixes looked like (releasing hand
authored the close in prose and dropped the savepoint bookend for two real
deliveries; separately, one session delivered four intents back to back and
never ran the old step-5 one-liner at all, intent 188). Never restate
outcome/INDEX/savepoint/disarm prose inline again; call `scripts/end-intent`.

### Step 0. Precondition (the gate is section-blind, not selective)

`Bridge.check_gate` (scripts/lib/bridge.rb) is LIVE code already wired into
the write-time hook. Its outcome.md rule is a blind scan of the WHOLE
checklist.md: `content.scan(/^- \[ \]/)` counts every unchecked box, in
every section, with no awareness of which section a box lives in. ANY
unchecked box anywhere blocks the outcome.md write; there is no exemption
for orchestrator-owned or completion-tracking items.

1. Read checklist.md. Tick every item as it is actually performed, including
   an item that describes the close itself: running this very procedure IS
   what that item describes, so tick it at the moment you begin the close,
   before authoring outcome.md. By the time outcome.md is written,
   checklist.md must read 100 percent checked; there is no other way past
   the gate.
2. Confirm every acceptance criterion in spec.md is verifiable (tests pass,
   or the manual check described in its HOW line was actually run).
3. The structure gate (intent 222) now enforces this: `scripts/end-intent`
   refuses with exit 6 and names the exact unchecked box (or any other
   structural gap: intent-file validity, lifecycle-artifact presence,
   `## Links` projection). On a refusal, fix via the OWNING tool, never a
   hand edit of the check's own output:
   - checklist/outcome content - finish it yourself, the same as before.
   - links projection - `scripts/project-links --intent <id> --apply` via
     `maintenance-run`.
   - a savepoint issue - advisory only (WARN, never blocks): run
     `plastic-intent-savepoint` to rebuild via `Bridge.rebuild_savepoint` if
     you want it clean, but it never refuses the close on its own.
   Then re-run `scripts/end-intent`.

### Step 1-5. Run `scripts/end-intent`

First author outcome.md for real (never leave the scaffold placeholder in
place): copy `templates/outcome.md`, set the frontmatter to
`disposition: delivered` or `disposition: abandoned`, and fill `## Summary`,
`## Delivered`, `## Verification`, `## Follow-ups`. On abandon, `## Summary`
states the abandonment reason and the trail (see Pivot below). Also author
the rich INDEX entry note now (a short line in the store's existing
Completed/Abandoned convention: mode/tier, what shipped or why it was
abandoned, suite result, merge/spawn notes); content authoring stays with
you, `--index-note` only appends what you write.

Then call the script once:

```bash
ruby ~/.plastic/scripts/end-intent \
  --store <store_path> --id <intent_id> --disposition delivered|abandoned \
  --session "$CLAUDE_CODE_SESSION_ID" \
  --outcome-summary "<one-line ## Outcome summary for the intent file>" \
  --index-note "<rich Completed/Abandoned entry description>"
```

This does all of steps 1-5 in order: guards outcome.md (refuses a missing,
still-placeholder, or wrong-disposition file with exit 2 and authors
nothing), stamps the intent file's `## Outcome` section, moves the INDEX.md
line from `## Active` to `## Completed` or `## Abandoned` (dated today,
idempotent, accepting either a real em dash or a plain hyphen as the id/
title separator on read while always emitting the real em dash on write)
with the `--index-note` text appended after the date so the entry stays
rich, appends the savepoint `Done` bookend, commits the store repo, and
disarms (releases the code worktree and clears `delivery.lock`, verified
against the durable lock file on disk, never merely trusted). Omit
`--index-note` for a thin id+date entry, add `--no-commit` when a separate
commit step already covers the store (this never skips disarm), and
`--dry-run` to preview steps 1-5 with no writes.

A pre-flight lock guard runs before anything is written: it resolves the
calling session (`--session`, else `CLAUDE_CODE_SESSION_ID`, else the
existing lock's own recorded owner, else a no-op) and checks it against any
existing `delivery.lock`. A live foreign session refuses the whole run
(exit 4, nothing written); a stale foreign lock is reclaimed automatically
(audited to savepoint.md) and the run proceeds as the new owner. Before
removing the worktree, step 5 also refuses on an unexpectedly dirty code
worktree (exit 5, naming the worktree path) rather than force-discarding
uncommitted changes; pass `--discard-worktree-changes` only when you mean
to override that deliberately.

On the auto mode / curator path (no release), this single call performs the
FULL disarm (plain worktree remove, since the branch survives for later
reclaim). On a release-shipped path, `skills/releasing/SKILL.md` merges and
removes the worktree FIRST (its own step 8, merge-then-remove) before ever
calling this script, so by the time this call's step 5 runs, the worktree is
already gone (a harmless no-op) and only the lock is left to clear,
correctly, for the first time on that path (D7).

Exit codes: 0 success (the intent is closed AND its delivery lock is gone);
1 a usage or resolution failure, OR an INDEX id that resolves to neither
`## Active` nor the terminal section; 2 the outcome.md guard refusing (fix
outcome.md and re-run, nothing was written); 3 steps 1-4 already committed
but disarm could not verify the lock is gone afterward (run `/plastic-doctor
check the lock status`); 4 a live foreign session holds the lock (back off);
5 the code worktree is dirty (commit/stash first, or pass
`--discard-worktree-changes` deliberately).

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

`plastic-releasing`, `plastic-auto`, the curator agent, `store-curating`, and
`store-indexing` all delegate their mechanical close to this skill (or call
`scripts/end-intent` directly for steps 1-5). None of them restate the
outcome/INDEX/savepoint/disarm prose inline any more; if you find one that
does, that surface has drifted and should route here instead.
