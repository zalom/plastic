# End-Tail Mechanics: resolve_session and Disarm Ordering

Deep WHY/mechanics detail behind two spots in `SKILL.md`: how `arm_auto` resolves a
session id when arming the gate, and why the End-tail steps in Completion (release
worktrees, clear the lock, purge the bridge, reindex) run in that exact order.

## Table of Contents

- [resolve_session fallback internals](#resolve_session-fallback-internals)
- [Disarm ordering and worktree cleanup rationale](#disarm-ordering-and-worktree-cleanup-rationale)
- [QMD reindex ordering rationale](#qmd-reindex-ordering-rationale)

## resolve_session fallback internals

`arm_auto` calls `resolve_session`, which picks the first non-empty of: the explicit
id you pass -> `CLAUDE_CODE_SESSION_ID` -> a deterministic derived key (a hash of the
store and intent id). It never returns nil, so the gate engages even when every
session env var is empty; the call never needs a non-empty session env var to
function. Arming prints a one-line notice to stderr when it falls through to the
derived key.

Arming acquires the durable `delivery.lock` in the intent dir, keyed by that resolved
session. Ownership is session-keyed, not process-keyed, so the arm one-liner exiting
immediately is fine by construction: the lock stays yours for every later tool call in
this session. A failed arm raises with a message naming the resolving `plastic-lock`
verb.

## Disarm ordering and worktree cleanup rationale

Disarm runs the ordered End tail: it releases the worktrees first, then clears the
intent's `delivery.lock` (and the bridge's lock cache), and only then is the bridge
purge-eligible. Disarming also purges stale bridge files from the temp directory
automatically (it keeps the current bridge, any live run, and any bridge whose intent
still holds a delivery lock), so no manual `/tmp` cleanup is needed.

**Worktree cleanup (mandatory, intent 73c3).** Disarming performs the worktree release:
`disarm_auto` calls `Worktree.release`, which removes both per-intent worktrees (the code
worktree under `<repo>/.claude/worktrees/{id}--{slug}` and the paired store worktree under
`<plastic_home>/.worktrees/{id}--{slug}`), prunes both repos, and clears the worktree block
from the bridge. This is the plain remove path: the disarm route does NOT merge, so use it
only when no release merges the branch (the branch survives and can be reclaimed).

When the work is being shipped through a release, do NOT rely on this plain remove. The
release path (Completion step 4, via `plastic-releasing`) is responsible for merging the
intent's code branch (`plastic/{id}--{slug}`) back to the repo's default branch BEFORE the
worktree is removed, so the integrated work is not lost. It does this with
`Worktree.finish(bridge_data, merge: true)` (merge-then-remove). Never leave an orphaned
worktree, and run `git worktree prune` if you hit a stale reference.

## QMD reindex ordering rationale

Completion is the lifecycle event that keeps the search index fresh. `<store-root>` is
the store that holds this intent (the global store or the project store). The reindex is
the LAST End-tail step, run after purge, so the index never references a bridge or lock
that is about to disappear (see PLASTIC.md `## Delivery Isolation and the Single-Owner
Lock`).
