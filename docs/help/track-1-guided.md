# Track 1: Guided, your first intent

## Who it is for and what you will have done

For a new user who wants to feel the whole cycle once, one stage at a time, approving each
step before the next one starts. After this track, one small, real change will be delivered
end to end: a piece of work moved through What, Why, How, and Exec, with a finished
`outcome.md` to show for it.

## Before you start

Run `plastic update` first, so the commands below match what is
actually installed.

This track walks a graph intent: the plan is a `graph.md` of nodes that the runner dispatches.
For the simpler checklist path, a small Ruby example taken from a new intent to merged code and
a delivered close, run `plastic help tutorial` instead.

Work in a sandbox. Run `plastic intent new` outside any registered project and the intent lands
in the global store; run it inside a registered throwaway repository and it lands in that
project's store, and the close can check the merge. The worked example edits the repository's
README. With no repository, the deliverable is a short written note saved in the intent's own
directory (see station 5). Either way, nothing in this track touches a real project.

## Stations

### 1. Create the intent

Run `plastic intent new` and describe the work in plain words, for example "add a
short Usage section to this project's README."

Artifact: a new intent directory, `{id}--slug.md`, plus the sentinel placeholder lifecycle
files (`spec.md`, `plan.md`, `checklist.md`, `outcome.md`) and empty `actions/` and
`resources/` folders.

Checkpoint: open the new file. It already has a real id and a one-line description; nothing
was hand-typed into it directly. That is the point: intents are always scaffolded by the
tool, never written by hand.

### 2. Read where it stands

Run `plastic intent show ID`.

Artifact: none. The command only reads. It prints the intent's state screen, and its `next:`
line names the step to run: `plastic intent spec ID` while the intent has no spec or graph.
`plastic continue` reads the same way for the whole project. Neither takes a lock.

Checkpoint: name the step the `next:` line points at, and why.

### 3. Why, rulings one at a time

Run `plastic intent spec` (say "grill me" for a harder, interview-style pass over
the same ground). It asks conversational prose questions, one at a
time, never a multiple-choice menu, and answers them one at a time in return.

Artifact: each ruling lands as its own `## Insights` entry the moment it is made, never batched
for later, through `plastic intent rule ID "TEXT"`, stamped with the time, the `Why` stage and
the `human` author. `intent rule` writes nothing else: the agent edits `## Context` and any
`### Decisions` list by hand. This station's product is the enriched Why; neither command
writes `spec.md`.

Checkpoint: after two or three answers, look at the intent file. Every ruling given out loud
is already sitting in `## Insights`, in writing.

### 4. How, write the graph

In the same conversation, the agent turns the rulings into the graph. It writes `graph.md` from
`templates/graph.md`. No command creates it; once it exists, the runner behind
`plastic intent step` and `plastic intent answer` updates it.

Artifact: `graph.md` (nodes, edges, dispatch policy) and one `nodes/N.md` file per node this
small delivery needs. A delivery this size is one node; many independent tasks instead get
one node each, dispatched in parallel by the runner.

Checkpoint: open `graph.md` and point at the one node this worked example needs.

### 5. Exec, drive the runner loop

Run `plastic intent step ID`.

Graph execution needs the delivery lock. Without it, `intent step` names
`plastic auto start ID` as the next step. From a conversation session, `auto start` refuses with
exit 3 unless the owner approves `--allow-inline`; stop and report the refusal.

Teach the loop: `plastic intent step ID` runs the internal `runner step`, which computes which
nodes are ready and prints a spawn block to dispatch. Pass a returned node back with
`plastic intent step ID --return NODE=PATH`. `plastic intent answer ID --node NODE --decision
"TEXT"` closes a node that waits on an owner's ruling. The internal
`ruby ~/.plastic/scripts/runner status <intent_dir>` reads the ledger (running, done, blocked,
or waiting on a decision); no public command wraps it. Call `step` again after each
dispatched node returns, until the graph is empty.

Artifact: the actual change on disk (the new README Usage section, or, in the global-store
fallback, a short written note saved as the intent's deliverable) and every node in
`graph.md` at a terminal status.

Checkpoint: run `runner status` and confirm no node is left running or blocked, before
moving to station 6. When the graph is complete, `intent step` names `plastic intent verify ID`.

### 6. End

Run `plastic intent end ID --delivered --summary "TEXT"`. Add `--dry-run` first to see what
the close would do without writing anything.

When the intent has a code branch or worktree, merge the branch yourself first. Plastic does
not merge, and a delivered close refuses unmerged code with exit 1.

Artifact: a real `outcome.md` (Summary, Delivered, Verification, Follow-ups) generated from
`graph.md` and the ledger (the same model as the internal `scripts/outcome-report`), the
intent moved from `## Active` to `## Completed` in `INDEX.md`, the terminal savepoint line,
and the lock and worktree released.

Checkpoint: open `outcome.md` and read its Summary. It should describe, in a sentence or
two, exactly the README section (or note) just delivered.

## Wrap and where to go next

That is the full cycle once: create, graph, runner step, end. Run `plastic help tutorial` for
the checklist path with a merged code change. Read
[`your-first-intent-in-10-minutes.md`](https://github.com/zalom/plastic/blob/main/docs/guides/your-first-intent-in-10-minutes.md) for the same path condensed to a single
read, and [`reading-the-ledgers.md`](https://github.com/zalom/plastic/blob/main/docs/guides/reading-the-ledgers.md) for where each station wrote its
work down.
