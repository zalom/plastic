# End-Tail Mechanics: Arm.disarm and the Ordering

Deep mechanics behind two spots in `SKILL.md`: how `plastic-lock arm` resolves a session id
when it takes an intent, and why the End-tail steps in Completion (release the worktree, clear
the lock, reindex) run in that exact order. `scripts/lib/arm.rb` carries the arm, disarm, and
repair operations.

## Table of Contents

- [Session resolution](#session-resolution)
- [Disarm ordering and worktree cleanup rationale](#disarm-ordering-and-worktree-cleanup-rationale)
- [QMD reindex ordering rationale](#qmd-reindex-ordering-rationale)

## Session resolution

`Arm.resolve_session` picks the first non-empty of: the explicit id (`--session`, or the hook
stdin `session_id` when a caller has it), the `CLAUDE_CODE_SESSION_ID` the CLI read, then a
deterministic derived key (a hash of the store and the intent id). It never returns nil, so
the arm verb works even when every session variable is empty; a session-less arm and a later
session-less close resolve to the same key.

Arming acquires the durable `delivery.lock` in the intent dir, keyed by that resolved session
and stamped with `run_mode`. Ownership is session-keyed, not process-keyed, so the arm command
exiting is fine by construction: the lock stays yours for every later tool call in this
session, and the record hook refreshes its lease on every write you make. Holding that lock is
why the capture and record hooks stop treating your prompts as day-ledger items for the rest
of the delivery.

## Disarm ordering and worktree cleanup rationale

`Arm.disarm` runs the ordered End tail: it releases the worktree first, then clears the
intent's `delivery.lock` as its recorded owner. The worktree goes first so a released lock
never points at a checkout another session could claim; the lock goes last so the record
hook keeps heartbeating it until the delivery is actually done.

**Mechanized since intent 188.** `scripts/end-intent` performs this disarm itself, as its own
step 5, after steps 1-4 (outcome/INDEX/savepoint/commit) commit. A pre-flight lock guard
refuses on a live foreign session (exit 4) and reclaims a stale foreign lock automatically
(audited to savepoint.md); a dirty code worktree refuses before removal (exit 5,
`--discard-worktree-changes` overrides deliberately); and the durable lock file is checked
again after disarm, never merely trusted (exit 3 if it is somehow still present).

**Worktree cleanup (mandatory, intent 73c3).** `end-intent`'s step 5 calls `Arm.disarm` by
default, which calls `Worktree.release` on the block `Arm.worktree_block` derives from
`projects.yml` and the intent id, removing the intent's code worktree under
`<repo>/.claude/worktrees/{id}--{slug}` and pruning the repo. This is the plain remove path:
the disarm route does NOT merge, so use it only when no release merges the branch (the branch
survives and can be reclaimed).

When the work is being shipped through a release, do NOT rely on this plain remove.
`skills/releasing/SKILL.md` runs its worktree-merge step BEFORE its `end-intent` call, merging
the intent's code branch (`plastic/{id}--{slug}`) back to the repo's default branch BEFORE
the worktree is removed, via `Worktree.finish(Arm.delivery(intent_dir: ...), merge: true)`
(merge-then-remove), so the integrated work is not lost. By the time `end-intent`'s own step 5
runs afterward, the worktree is already gone (a harmless no-op) and only the delivery lock is
left to clear. Never leave an orphaned worktree, and run `git worktree prune`
if you hit a stale reference.

## QMD reindex ordering rationale

Completion is the lifecycle event that keeps the search index fresh. `<store-root>` is the
store that holds this intent (the global store or the project store). The reindex is the LAST
End-tail step, run after the disarm, so the index never references a lock that is about to
disappear.
