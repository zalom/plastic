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

Artifact: a new intent directory, `{id}--slug/` holding `intent.md`, the placeholder
files `spec.md` and `outcome.md`, `graph.json`, and empty `actions/` and `resources/`
folders.

Checkpoint: open the new file. It already has a real id and a one-line description; nothing
was hand-typed into it directly. That is the point: intents are always scaffolded by the
tool, never written by hand.

### 2. Read where it stands

Run `plastic intent show ID`.

Artifact: none. The command only reads. It prints the intent's state screen, and its `next:`
line names the step to run: `plastic intent spec ID` while the intent has no spec or graph.
`plastic graph resume` reads the same way for the whole store. Neither takes a lock.

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
`templates/graph.md`. No command creates it; once it exists, `plastic node done` and `plastic node resolve` update it.

Artifact: `graph.md` (nodes, edges, dispatch policy) and one `nodes/N.md` file per node this
small delivery needs. A delivery this size is one node; many independent tasks instead get
one node each, dispatched in parallel by the runner.

Checkpoint: open `graph.md` and point at the one node this worked example needs.

### 5. Exec, drive the graph loop

Run `plastic next`.

Graph execution needs the delivery lock. Without it, `plastic next` names
`plastic auto ID` as the next step. When that command exits 3, stop and report the refusal.

Teach the loop: `plastic graph ready ID` lists which nodes are ready. Close a finished node with
`plastic node done`. `plastic node resolve` reopens a node that waits on an owner's ruling.
`plastic graph show ID` reads the ledger (running, done, blocked, or waiting on a decision).
Call `plastic next` again after each node returns, until the graph is empty.

Artifact: the actual change on disk (the new README Usage section, or, in the global-store
fallback, a short written note saved as the intent's deliverable) and every node in
`graph.md` at a terminal status.

Checkpoint: run `plastic graph show ID` and confirm no node is left running or blocked, before
moving to station 6. When the graph is complete, `plastic next` names `plastic intent end ID`.

### 6. End

Run `plastic intent end ID`. It takes no options. It needs every live node done, every
criterion covered, an accepted verdict from `plastic intent judge ID` and
`plastic intent verdict ID accept TEXT`, and the merge and architecture map records under
Verification in outcome.md. Use `plastic intent abandon ID` for an intent that will not ship.

When the intent has a code branch or worktree, merge the branch yourself first. Plastic does
not merge, and a delivered close needs the `Merged:` line under Verification in outcome.md; Plastic does not check the merge itself.

Artifact: a real `outcome.md` (Summary, Delivered, Verification, Follow-ups) generated from
`graph.md` and the ledger (the same model as the internal `scripts/outcome-report`), the
intent moved from `## Active` to `## Completed` in `INDEX.md`, the terminal savepoint line,
and the lock and worktree released.

Checkpoint: open `outcome.md` and read its Summary. It should describe, in a sentence or
two, exactly the README section (or note) just delivered.

## Wrap and where to go next

That is the full cycle once: create, graph, node done, end. Run `plastic help tutorial` for
the checklist path with a merged code change. Read
[`reading-the-ledgers.md`](https://github.com/zalom/plastic/blob/main/docs/guides/reading-the-ledgers.md) for where each station wrote its
work down.
