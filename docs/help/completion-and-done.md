# Completion and the End Tail

This chapter holds what "intent done" means and the End-stage tail.

## What "intent done" means

An intent is done when its row says so: `plastic intent end` sets its status to `done` with the
disposition `delivered`, and `plastic intent abandon` sets it to `abandoned` with the
disposition `cancelled`, or `superseded` when another intent supersedes it. `store/index.json`
prints every intent's status and disposition from those rows.

`outcome.md` is mandatory at every terminal transition, delivered and abandoned alike. The
delivered path writes it with the result and its Verification lines; the abandoned path writes
why the intent is dropped and, for an intent that started, a `Reverted:` line.

`plastic intent end ID` takes no options. It closes the intent when the rows allow it:
every live node done, every criterion covered, an accepted verdict at or after the newest live
node change, and one delivery line under `## Verification` in outcome.md, as
[Store the delivered work](#store-the-delivered-work) describes. With `review.pull_request` set to `required`, it also needs a
`Pull request:` bullet and an `Approved:` bullet. An unapproved pull request is a refusal
(exit 3), and a live node claim of another session is a refusal (exit 3). Anything else that is
missing comes back as a handoff with exit 1, and nothing closes. The close does not reindex
QMD, and Plastic never merges or runs version control.

The completion row holds the judge `verdict` and the evidence built from the rows: each
criterion key with its done nodes and their findings. The close,
prints the intent files, and hands the agent the steps that stop the processes and agents the
intent started. `plastic intent abandon ID` closes an intent that will not ship, once
outcome.md says why. An intent that started also needs a `Reverted:` bullet; a future or open
intent with no node has nothing to revert. It writes no completion row.

Once the intent is closed, it takes no more rulings, nodes or verdicts: a done intent is never
moved back to active.

One report per audience: a delivery produces `outcome.md` plus one EM-to-CTO owner report, and
no other step restates either.

## You land the code

Plastic writes no commit itself and runs no version control. The agent commits in the
project's repository the way that repository's own `AGENTS.md` says, and records what landed
with `plastic intent note ID TEXT --kind Commit`, a line under Notes in `outcome.md`.

## Store the delivered work

`plastic intent end` closes an intent once outcome.md records how its work was delivered. The
Verification section holds one of three delivery lines:

| Line | Records | Also needs |
| --- | --- | --- |
| `Merged: <branch> into <base> at <commit or pull request>` | Code merged by a pull request | `Architecture map: <tool> at <source revision>` |
| `Committed: <branch> at <commit>` | Code committed straight to its branch, with a commit of 7 to 40 hexadecimal characters | `Architecture map: <tool> at <source revision>` |
| `Delivered: resources/output/<path> because <reason>` | Work that no version control holds, such as a report or a document | Nothing more |

Delivered files go in the intent folder: reports under `resources/output/reports`, and other
files under `resources/output/files`. `resources/output/reports` holds only the reports the owner
asked for and the reports the setting `reports.mandatory` names. Record an asked report with
`plastic intent report ID PATH --asked WORDS`: the words must appear in an owner message of the
store, the intent or the session, or the command exits 3 and writes nothing. A mandatory report
takes the same command without `--asked`. The command adds one line for the report under
`## Reports` in outcome.md. Tool output, packets, plans and notes go to `resources/tmp`, and
copies of outside material go to `resources/references`. The `Delivered:` line counts only when the path it names
exists there. Code always takes `Merged:` or `Committed:`, never `Delivered:`.

A line counts only when it is filled in: one that starts with a denying word such as `no`,
`pending` or `n/a`, or still holds a placeholder such as `<commit>`, is refused, and the handoff
names it. Run `plastic sync up` after editing outcome.md, then `plastic intent end ID` again.

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
