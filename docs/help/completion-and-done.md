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
missing comes back as a handoff with exit 1, and nothing closes.
Plastic never merges or runs version control.

The completion row holds the judge `verdict` and the evidence built from the rows: each
criterion key with its done nodes and their findings. The close,
prints the intent files, and hands the agent the steps that stop the processes and agents the
intent started. `plastic intent abandon ID` closes an intent that will not ship, once
outcome.md says why. An intent that started also needs a `Reverted:` bullet; a future or open
intent with no node has nothing to revert. It writes no completion row.

Once the intent is closed, it takes no more rulings, nodes or verdicts: a done intent is never
moved back to active.

A delivery produces `outcome.md`. It adds a report only by the rule in "Which work records a
report" below, and no other step restates either.

## You land the code

Plastic writes no commit itself and runs no version control. The agent commits in the
project's repository the way that repository's own `AGENTS.md` says, and records what landed
with `plastic intent note ID TEXT --kind Commit`, a line under Notes in `outcome.md`.

## Store the delivered work

`plastic intent end` closes an intent once outcome.md records how its work was delivered. The
Verification section holds one of three delivery lines:

| Line | Records | Also needs |
| --- | --- | --- |
| `Merged: <branch> into <base> at <commit or pull request>` | Code merged by a pull request | Nothing more |
| `Committed: <branch> at <commit>` | Code committed straight to its branch, with a commit of 7 to 40 hexadecimal characters | Nothing more |
| `Delivered: resources/output/<path> because <reason>` | Work that no version control holds, such as a report or a document | Nothing more |

Delivered files go in the intent folder: reports under `resources/output/reports`, and other
files under `resources/output/files`. Record a report with `plastic intent report ID PATH`. The
command adds the line `- PATH` under `## Reports` in outcome.md, and the sync reads the report.
A report the setting `reports.mandatory` names takes the same command. The `Delivered:` line
counts only when the path it names exists there. Code always takes `Merged:` or `Committed:`,
never `Delivered:`.

### Which work records a report

The rule lives in this guidance. The command checks the path, the file type and that the intent
is open, and then records; it does not judge whether the work needed a report.

| Kind of result | Report? |
| --- | --- |
| Research, a comparison of options, a review or audit where the review is the work, a proposal for a ruling | Yes, with no ask |
| A plan, a delivery report, an explainer | Only when the owner asks for one, or `reports.mandatory` names it |
| A product file the work makes | No: it goes to `resources/output/files` |
| A working file, a link list, a part of a research job | No: it goes to `resources/tmp`; only the synthesis is the report |

To tell which kind the work is, read three things:

- The words of the request. "Report", "artifact" and "html" ask for a report. "Research",
  "compare", "audit" and "verify" name the work, whose synthesis is the report.
- The kind or the title of the intent.
- Whether the result is a finding or code. A finding is reported; code is merged or committed.

Tool output, packets, plans and notes go to `resources/tmp`, and copies of outside material go
to `resources/references`.

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
