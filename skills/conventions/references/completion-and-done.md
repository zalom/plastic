# Completion and Done

This chapter holds what "intent done" means and the End-stage tail.

#### What "intent done" means (intent 93)

Done is one law with three signals, and they must agree. INDEX `## Completed` /
`## Abandoned` is the single canonical terminal marker: it is the store-wide ledger a fresh
session reads first, so it wins on any conflict. `outcome.md` is the "deliverable exists"
signal, and the savepoint `Done delivered|abandoned` line is the audit echo. All three must
agree; when they disagree, INDEX is authoritative and `doctor` flags the mismatch (the
`done_signals` check: `outcome.md` real but still under `## Active`, or terminal without a
real `outcome.md`, or a terminal intent whose savepoint carries no `Done` line).

`outcome.md` is mandatory at every terminal transition, delivered and abandoned alike. It
self-declares its disposition through a `disposition: delivered|abandoned` frontmatter
header. The delivered path authors it with the result; the abandoned path authors it with
the abandonment reason and no longer leaves the scaffolded placeholder sentinel in place.

The canonical End tail runs in this order, and the QMD reindex is always LAST, after the
purge: `outcome.md -> INDEX terminal -> savepoint Done -> commit -> disarm (Worktree.release
-> Lock.release -> purge) -> QMD reindex`. Running the reindex last keeps the index from
ever referencing a bridge or lock that disarm is about to remove.

`scripts/end-intent` performs this order's disarm step (verify the code worktree is clean,
then merge/remove worktrees, then clear the lock) as its own step 5, mechanically, since
intent 188: a session no longer needs a separate one-liner for it, and the script's own
exit code (0) is the single fact a caller needs that the intent is closed AND its delivery
lock is gone. A pre-flight lock guard runs before anything is written (refuses a live
foreign session, reclaims a stale one with an audit line), and a dirty code worktree
refuses before removal rather than force-discarding uncommitted changes.

The post-done access window is lock-bounded: `[INDEX terminal -> Lock.release]`. Through it
the completing session keeps full read and write access to the terminal directory and no
purge can fire (108's lock-held keep-guard keeps the bridge while `delivery.lock` exists).
Once the lock is released the window closes: the bridge becomes purge-eligible and the
directory is frozen. A crash mid-tail is recovered by stale-lock reclaim plus finishing the
tail; `doctor` surfaces this as a "stalled completion" (terminal in INDEX but the lock is
still present or stale). Finishing the tail is FINISHING a completion, never a reactivation:
a done intent is never moved back to `## Active`.
