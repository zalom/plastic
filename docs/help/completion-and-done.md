# Completion and the End Tail

This chapter holds what "intent done" means and the End-stage tail.

#### What "intent done" means (intent 93)

Completion is one law with three signals, and they must agree. INDEX `## Completed` /
`## Abandoned` is the single canonical terminal marker: it is the store-wide ledger a fresh
session reads first, so it wins on any conflict. `outcome.md` is the "deliverable exists"
signal, and the savepoint's terminal `delivered|abandoned` line is the audit echo. All three
must agree; when they disagree, INDEX is authoritative and `doctor` flags the mismatch (the
`done_signals` check: `outcome.md` real but still under `## Active`, or terminal without a
real `outcome.md`, or a terminal intent whose savepoint carries no terminal disposition line).

`outcome.md` is mandatory at every terminal transition, delivered and abandoned alike. It
self-declares its disposition through a `disposition: delivered|abandoned` frontmatter
header. The delivered path authors it with the result; the abandoned path authors it with
the abandonment reason and no longer leaves the scaffolded placeholder sentinel in place.

The canonical End tail runs in this order: `outcome.md -> INDEX terminal -> the terminal
savepoint line -> commit -> disarm (Worktree.release -> Lock.release)`. `plastic intent end`
runs all of it through `scripts/end-intent`. The close does not reindex QMD: no public close
path calls `qmd-sync`, so the QMD index catches up only when you run `qmd-sync` yourself.

`scripts/end-intent` never merges code. Before a delivered close writes anything, it checks
that the intent's code is already merged into the current branch of the repo checkout. It
checks the commit the code worktree is on, even when that worktree is on a renamed branch or
a detached HEAD, and it checks the code branch after the worktree is gone. The repo checkout
must be on the branch you release from, not detached and not on the code branch. If the code
isn't merged, or Git can't tell, the script exits 9 and changes nothing: INDEX, the savepoint, the
lock, and the worktree all stay as they were. `plastic intent end` reports that refusal as exit 1
with a named message. `--dry-run` refuses the same way. The refusal
names the merge to run, for example `git -C <repo> merge plastic/<id>--<slug>`. Run that
ordinary merge, or release the work through your usual process, and then run the close
again. An abandoned close and an intent with no code repository skip this check.

A delivered close also refuses, as exit 1, an untouched scaffold (script exit 8) and a hollow
report whose `## Delivered` rows do not match the action files (script exit 7). A live foreign
lock is script exit 4, which `plastic intent end` reports as exit 3.

`scripts/end-intent` performs this order's disarm step (verify the code worktree is clean,
then remove the worktree, then clear the lock) as its own step 5, mechanically, since
intent 188: a session no longer needs a separate one-liner for it, and the script's own
exit code (0) is the single fact a caller needs that the intent is closed AND its delivery
lock is gone. A pre-flight lock guard runs before anything is written (refuses a live
foreign session, reclaims a stale one with an audit line), and a dirty code worktree
refuses before removal rather than force-discarding uncommitted changes.

The post-done access window is lock-bounded: `[INDEX terminal -> Lock.release]`. Through it
the completing session keeps full read and write access to the terminal directory (108's
lock-held keep-guard holds it open while `delivery.lock` exists). Once the lock is released
the window closes and the directory is frozen. A crash mid-tail is recovered by stale-lock
reclaim plus finishing the tail; `doctor` surfaces this as a "stalled completion" (terminal in
INDEX but the lock is still present or stale). Finishing the tail is FINISHING a completion, never a reactivation:
a done intent is never moved back to `## Active`.

One report per audience: a delivery produces `outcome.md` plus one EM-to-CTO owner report, and
no other step restates either (see `plastic help human-report-contract`).

#### The pull request description

A pull request that closes a delivery carries four headings, in this order:

- **What.** The change, in one paragraph.
- **Why.** The problem or the ruling behind it, with the date when one matters.
- **How.** Each file or area and what changed there.
- **Tests.** The test files run and their result, and a note that CI runs the full suite.

Plain words throughout. No AI attribution anywhere in the title or the body.

A repository's own pull request template is honored, never rewritten. The project's
`flow.pull_request_body` in `project.yml` decides how: `inject` (the default) puts the four
headings after the template, and `template` sends the template alone. A repository with no
template gets the four headings under either value.

Write the description to a file first and pass the file to the pull request. When the
project or the person runs a writing checker, the file passes it before it is used.
