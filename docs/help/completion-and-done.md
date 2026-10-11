# Completion and the End Tail

This chapter holds what "intent done" means and the End-stage tail.

## What "intent done" means

An intent is done when its row says so: `plastic intent end` sets its status to `done` with the
disposition `delivered`, and `plastic intent abandon` sets it to `abandoned` with the
disposition `cancelled`, or `superseded` when another intent supersedes it. `store/index.json`
prints every intent's status and disposition from those rows.

`outcome.md` is mandatory at every terminal transition, delivered and abandoned alike. The
delivered path writes it with the result and its Verification lines; the abandoned path writes
why the intent is dropped and a `Reverted:` line.

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

Once the intent is closed, it takes no more rulings, nodes or verdicts: a done intent is never
moved back to active.

One report per audience: a delivery produces `outcome.md` plus one EM-to-CTO owner report, and
no other step restates either.

## You land the code

Plastic writes no commit itself and runs no version control. The agent commits in the
project's repository the way that repository's own `AGENTS.md` says, and records what landed
with `plastic intent note ID TEXT --kind Commit`, a line under Notes in `outcome.md`.

## The pull request description

A pull request that closes a delivery carries four headings, in this order:

- **What.** The change, in one paragraph.
- **Why.** The problem or the ruling behind it, with the date when one matters.
- **How.** Each file or area and what changed there.
- **Tests.** The test files run and their result, and a note that CI runs the full suite.

Plain words throughout. No AI attribution anywhere in the title or the body.

A repository's own pull request template is honored, never rewritten: the four headings go
after it. Writing the description to a file before passing it to the pull request tool is the
agent's own step.
