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

Read `../plastic-conventions/references/completion-and-done.md` for what "intent done" means and
the End-stage tail behind the steps below. This path resolves relative to this skill's own
installed directory.

## The 8 steps (0-7)

| # | Step | Who does it |
|---|---|---|
| 0 | Precondition check | You, before touching outcome.md |
| 1 | backfill spec/plan/action/outcome from the record, self-check, intent-file `## Outcome` summary | `scripts/end-intent` |
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

### Step 0. Precondition (the record is what gets backfilled)

Nothing refuses the close any more (the 1.x write-time gate and `end-intent`'s
exit-6 structure gate were retired in 2.0, intents 302 and 308). What you leave
on disk is what the record becomes, so before the call:

1. Read checklist.md. Tick every item as it is actually performed, including
   an item that describes the close itself: running this very procedure IS
   what that item describes. An unchecked box is not a refusal, it is a
   reported gap that lands verbatim in the backfilled `## Follow-ups`.
2. Confirm every acceptance criterion in spec.md is verifiable (tests pass,
   or the manual check described in its HOW line was actually run).
3. Decide what you have to say. A spec.md, plan.md, action file, or outcome.md
   left as the scaffold placeholder is written from the record by
   `scripts/end-intent` (the intent file's `## Intent`, `### Decisions`, and
   `## Insights`, the checklist, the diff on the intent's own worktree). A
   file you wrote, even under a still-present sentinel, is never touched.
   Write outcome.md yourself when the summary deserves more than the
   `--outcome-summary` line; otherwise let the backfill carry it.

### Step 1-5. Run `scripts/end-intent`

Author outcome.md yourself when it deserves prose: copy `templates/outcome.md`,
set the frontmatter to `disposition: delivered` or `disposition: abandoned`, and
fill `## Summary`, `## Delivered`, `## Verification`, `## Follow-ups`. `## Delivered` is a
`| Row | What |` table: one row per thing delivered, in plain wording a reader
recognizes, not a method name or an implementation summary (that detail
belongs in `## Summary`). Each row's label must appear as a standalone token
in an action-file heading (`### S1 - ...` proves row S1); that heading's
matrix rows become the row's Proven-by cell on `report-screen delivered`'s
post-delivery screen. `## Needs you` is the literal None or a
`| N | What | Why |` table. On abandon, `## Summary` states the abandonment reason and the trail (see Pivot
below). A placeholder outcome.md is backfilled from the record instead, with the
close's disposition and the `--outcome-summary` line as its summary. Also author
the rich INDEX entry note now (a short line in the store's existing
Completed/Abandoned convention: mode, what shipped or why it was
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

This does all of steps 1-5 in order: backfills every missing or placeholder
spec.md, plan.md, action file, and outcome.md from the record (never a file
you wrote), runs doctor's per-intent structure check and the outcome guard as
a self-check that reports on stderr and proceeds (an unchecked box, a
malformed intent file, a wrong-disposition outcome.md you wrote), stamps the
intent file's `## Outcome` section, moves the INDEX.md
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
`## Active` nor the terminal section; 3 steps 1-4 already committed
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

### Step 7. Print `delivered`

Print `ruby ~/.plastic/scripts/report-screen delivered <intent_dir>` as the first characters
of the reply: nothing before it, no fence, or the hook cannot paint it. Asked, Delivered (with
its Proven-by column), Evidence, and Needs you come straight from the record - the EM-to-CTO
report, impact and risk first, in plain language, with the decision left to the human (merge,
release, or accept). See `outcome.md` for the details; do not restate it verbatim.

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

`plastic-releasing`, `plastic-auto`, and `plastic-intent-executing` all delegate their mechanical
close to this skill (or call `scripts/end-intent` directly for steps 1-5).
None of them restate the outcome/INDEX/savepoint/disarm prose inline any
more; if you find one that does, that surface has drifted and should route
here instead.
