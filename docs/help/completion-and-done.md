# Completion and the End Tail

This chapter holds what "intent done" means and the End-stage tail.

## What "intent done" means

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

`plastic intent end ID` takes no options. It closes the intent when the rows allow it:
every live node done, every criterion covered, an accepted verdict at or after the newest live
node change, and `Merged:` and `Architecture map:` bullets under `## Verification` in
outcome.md. With `review.pull_request` set to `required`, the default, it also needs a
`Pull request:` bullet and an `Approved:` bullet. An unapproved pull request is a refusal
(exit 3), and a live lock of another session is a refusal (exit 3). Anything else that is
missing comes back as a handoff with exit 0, and nothing closes. The close does not reindex
QMD, and Plastic never merges or runs version control.

The completion row holds the judge `verdict` and the evidence built from the rows: each
criterion key with its done nodes and their findings. The close releases the delivery lock,
prints the intent files, and hands the agent the steps that stop the processes and agents the
intent started. `plastic intent abandon ID` closes an intent that will not ship, once
outcome.md holds a `Reverted:` bullet; it writes no completion row.

The post-done access window is lock-bounded: `[INDEX terminal -> Lock.release]`. Through it
the completing session keeps full read and write access to the terminal directory (108's
lock-held keep-guard holds it open while `delivery.lock` exists). Once the lock is released
the window closes and the directory is frozen. A crash mid-tail is recovered by stale-lock
reclaim plus finishing the tail; `doctor` surfaces this as a "stalled completion" (terminal in
INDEX but the lock is still present or stale). Finishing the tail is FINISHING a completion, never a reactivation:
a done intent is never moved back to `## Active`.

One report per audience: a delivery produces `outcome.md` plus one EM-to-CTO owner report, and
no other step restates either (see `plastic help human-report-contract`).

## Session commit records the item, you land it

`plastic session note "SUMMARY" --kind Commit` is how a verified checklist item gets recorded.
It appends one `Item` savepoint line to the day ledger and
prints, as its `next:` line, the exact instruction to run. Plastic writes no commit itself: no
`git`, no `gh`, no `glab`.

Outside a registered project the instruction points at this page and names no repository.
Inside one, it names the project's path and says to commit there the way that repository's own
`AGENTS.md` says -- the project owns its own commit conventions, this page does not restate
them.

## The pull request description

A pull request that closes a delivery carries four headings, in this order:

- **What.** The change, in one paragraph.
- **Why.** The problem or the ruling behind it, with the date when one matters.
- **How.** Each file or area and what changed there.
- **Tests.** The test files run and their result, and a note that CI runs the full suite.

Plain words throughout. No AI attribution anywhere in the title or the body.

A repository's own pull request template is honored, never rewritten. `session commit`
detects one for you: when the project's repository holds a template at any path GitHub or
GitLab reads it from, the printed instruction includes the exact command that uses it --
`gh pr create --template NAME.md` or `glab mr create --template NAME` -- one line per template
found. A repository with no detected template gets a line pointing back at this page instead.
Either way, filling in the four headings above, and writing the description to a file before
passing it to the pull request tool, is the agent's own step; Plastic only names the command.
