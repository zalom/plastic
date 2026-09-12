---
name: plastic-intent-executing
description: Use when you have a graph or a plan to execute. A graph delivery runs on
  `scripts/runner`'s three verbs, `step`, `status`, and `answer`; older, non-graph work
  dispatches the `plastic-executor` agent for one consolidated action.
user-invocable: true
---

# Executing a Plan

## Step 0: Sync Worktree First

Before touching any file the graph or the plan names, sync the code worktree with main so no
edit lands on a path a merged rename or delete already removed:

```
git -C <worktree> fetch origin && git -C <worktree> merge --ff-only origin/main
```

If a named file or directory is missing (renamed or removed upstream), stop and report it
rather than editing a stale path. Read
`../plastic-conventions/references/locks-and-worktrees.md` for delivery isolation before
touching the worktree above.

## step

`ruby scripts/runner step <intent_dir>` computes which nodes in `graph.md`/`nodes/*.md` are
ready, applies dispatch policy (model, call cap), and prints a spawn block per dispatched node
- agent, model, packet path, the one test command, the call cap - fenced in its own stdout.
The runner itself never spawns an agent (327 D42). Call `step` again after each dispatched
node returns.

### Graph dispatch: the paste

The dispatch step is the paste, not a lead's hand-typed brief: copy each spawn block into the
Agent tool as its own dispatch, verbatim.

On Claude Code, the session spawns each dispatched node as a background subagent of its
per-kind agent (`plastic-node-work`, `plastic-node-verify`, `plastic-node-research`) named in
the spawn block. On Codex, one node runs over `codex exec` in a sandbox scoped to its kind and
writes only a return file, which the next `step` absorbs the same way it absorbs a Claude Code
return.

## status

`ruby scripts/runner status <intent_dir>` renders the graph's ledger state: which nodes are
running, done, blocked, or waiting on a decision. Safe to poll constantly; read node status
through `NodeLedger.status` before dispatching anything, never re-derive it by eye.

## answer

`ruby scripts/runner answer <intent_dir> --node <id> --decision "<text>"` closes a
`needs_decision` node with the owner's ruling, recorded to the ledger, so `step` can resume
the graph past it.

## Non-graph work

When the intent has no `graph.md`, dispatch ONE `plastic-executor` subagent with the whole
consolidated action pasted in (never a file reference): every task's full text, every action
file with its failure-mode matrix, the checklist items it must tick, the project context, and
the worktree path. It writes the matrix's tests and commits them red, implements the
consolidated action in order, ticks each item as it lands (see `## Tick-as-you-land`), and
drives the test suite green. Read its response by code: DONE or DONE_WITH_CONCERNS proceeds;
NEEDS_CONTEXT provides the missing context and re-dispatches; BLOCKED stops and reports.

## Tick-as-you-land

A tick is two edits, made together: mark the item's box `[x]`, and move its
checklist item from `## In Progress` to `## Completed` in `checklist.md`;
then add one `## Session Log` row (Date, Items Completed, Notes). The box is
the half the state screen's Progress bar reads: `IntentScreen::ITEM_RE` and
`progress_fields` count `[x]`, not which section the line sits in, so a line
moved to `## Completed` with its box left unmarked still reads as zero
progress. Do not batch several tasks' worth of checklist updates into one
later edit; tick the moment the task is verified, before moving to the next
task.

## Position in the cycle

- **Before:** the graph (`graph.md`, `nodes/*.md`), or `plan.md`/`checklist.md`, exists; the
  worktree is armed.
- **Produces:** code changes and a ticked checklist.
- **Next:** `plastic-intent-ending` owns `outcome.md`, generated through
  `scripts/outcome-report`, and the rest of the mechanical close.

Read `../plastic-conventions/references/lifecycle-and-savepoints.md` for the subagent
report-home contract this handoff relies on.
