# Agent Architecture

## Main Orchestrator

The Main Orchestrator manages the global store (Main Knowledge Base). It:
- Recognizes, creates, updates, and groups intents
- Spawns Project Orchestrators for registered projects
- Receives contributions back from Project Orchestrators
- Is the only agent that runs in a loop (continuous Build, Observe, Repeat)

## Project Orchestrators

Project Orchestrators manage project stores (Project Knowledge Bases). They:
- Care about intents and execution within their project
- Run an auto team to deliver an intent, as its main session
- Contribute back to the Main Orchestrator when new intents are born
  that could enrich the Main Knowledge Base

## The Main Session

The main session is the session the person talks to. It is the only session that runs
Plastic's hooks, so it is the only one that writes Plastic state: the lock, the rulings, the
spec, the work nodes and their results, the verdict and the close. Every agent it dispatches is
a node: it does one step and reports back. The main session judges each report, resolves every
ambiguity, and picks the next node.

| Step | Command |
| --- | --- |
| take the delivery lock | `plastic auto ID` |
| record each ruling | `plastic intent rule ID TEXT` |
| write spec.md and add the work nodes | `plastic node add ID TITLE --criterion KEY` |
| claim each node as you dispatch it | `plastic node claim ID NODE` |
| judge each node's report and record it | `plastic node done ID NODE TEXT` |
| judge the intent | `plastic intent judge ID` |
| close the intent after the merge | `plastic intent end ID` |

`plastic intent brief ID`, the step `plastic auto ID` offers next, prints the same steps for
the intent. Dependencies between nodes go in with `plastic edge add`. A report that names a
failure, a question, an impediment or new work is recorded with `plastic node fail`,
`plastic node ask`, `plastic node impede` or `plastic node add`. Claiming a node as it is
dispatched keeps the lock live while the agent works, even when the main session has no turns
(see `plastic help locks-and-worktrees`).

At each dispatch the main session passes the agent's model as the dispatch call's model: the
`model:` in the agent's frontmatter, or an `agents.models.<name>` override from config. Run
the main session itself on the best thinking model available; the agents keep their own
models, and none resolves to Fable unless a config override names it.

## The Auto-Mode Team

Auto mode runs one team per intent. The main session orchestrates it; the team members are
nodes it dispatches one at a time:

- **plastic-planner**: drafts the plan (the spec text, one action with its failure-mode
  matrix, and the proposed work nodes), or reviews a plan or a diff, and returns the result
  in its report. The main session writes the record from the report.
- **plastic-executor** (Exec): commits the matrix's tests red, implements the nodes with a
  commit each, drives the suite green, and reports each node's findings.
- **the plan reviewer**: a fresh planner on the prompt that `plastic help plan-reviewer-prompt`
  prints, dispatched before any code exists. It is never the planner that drafted the plan.
- **the post-execution reviewer**: a fresh planner on the prompt that
  `plastic help code-quality-reviewer-prompt` prints, dispatched only when a review rule in
  this chapter fires; never the maker.

One executor dispatch is the minimum delivery; the plan reviewer is a second dispatch before
code, and the post-execution reviewer is a third only when risk calls for it. No dispatched
agent takes a lock, claims a node, writes a record or closes an intent.

### Handoff Contracts

The main session hands each node one context bundle: the brief, the spec decisions, the action
with its matrix, the nodes it claimed for that agent, and the worktree path. The executor hands
back the code, the red and green commits, each node's findings and its completion report.
Dispatch is sequential on a single branch, because the deliverables share files.

The chain: intent `## Intent` / `## Context`, then the rulings, then `spec.md`, then
`actions/` plus the work graph, then the plan review, then the code changes and each node's
recorded result.

### Completion Reports

Every dispatched agent ends its turn with a structured completion report as its final message
(its return value), so the agent that did the work is the one that accounts for it. The report
carries a common envelope plus a role-specific payload: the planner returns the plan or the
review, the executor reports what was built and the test result. The format lives in
`plastic help agent-report-contract`.

Immediately after an agent returns and before the next dispatch, the main session judges the
return. A usable report means the node finished, and the main session records its result. A
blocked or errored return, or one with no usable report, is recorded as a failure with
`plastic node fail` and stops the handoff under the normal error procedure.

### Review Ownership

The main session owns every review decision: it dispatches the plan reviewer before code,
takes the review into its own record, and decides from the risk rule whether the
post-execution reviewer runs. Neither reviewer is ever the maker of what it reviews.
No hook blocks a write: the lock, the worktree, and the record are how the team keeps one
delivery in one place.

### The risk list

The post-execution reviewer runs when the executor's diff touches any of these paths:

- `hooks/`, `scripts/lib/plastic/hooks/`, `scripts/lib/hook_registry.rb`
- `scripts/lib/plastic/graph/lock.rb`, `scripts/lib/plastic/workflows/start_auto.rb`,
  `scripts/lib/plastic/graph/work/completion/writer.rb`
- `scripts/lib/installer_core.rb`, `scripts/install.rb`, `scripts/install-release`
- `package.json`, `CHANGELOG.md`

Grow this list here.

### Headless Note

In a headless or background run the session id may be unset. `plastic auto ID` then keys the
lock by a derived session key, and the main session verifies state from the rows and the files
(`plastic intent lock status ID`, the diff) rather than from a hook it assumes fired.

### Fallback by Case

If the harness supports agent dispatch, the main session dispatches each node through it. If
the harness has no agent dispatch at all (Codex CLI today), the main session walks the steps
itself: it still writes the matrix and the tests first, and reviews its own plan against the
matrix before code, saying so in `## Insights`.

## Two Modes

- **Human-driven:** Human chats with the Main Orchestrator, creates intents, thinks them
  through, then the Main Orchestrator dispatches Project Orchestrators and teams for execution.
- **Autonomous:** Human gives the Main Orchestrator a starting intent with defined outcomes.
  The auto team runs the full cycle, then the orchestrator spawns next intents and dispatches
  again.

## Autonomous Delivery

Human owns What and Why for human-initiated intents. The team assists (research, exploration)
but the human drives until handoff. When Why is complete, or the human runs
`plastic auto ID`, the auto team takes over How and Exec autonomously.

- **Safe-by-default:** the executor always prefers non-destructive routes (rename vs delete,
  additive migrations, backups before changes). Destructive actions on existing projects
  require human approval unless `--skip-permissions` is set.
- **Notification only on:** the How briefing, finish, or hard stop (blocked on destructive
  action, unresolvable error). No progress reports, `## Insights` tracks everything.
- **Greenfield autonomy:** during initial project creation, all decisions are non-destructive
  (nothing to destroy), so the team has full autonomy for greenfield choices.
- **Autonomous decisions** are logged in `## Insights` with the `(autonomous)` marker.

## Coordinator Loop

When "work on Project X":
1. Read `projects.yml`, find the project path
2. Load global config (defaults)
3. Load project config (overrides)
4. Read the global store's intents in its `store/index.json`, and find the ones about the project
5. Read the project store's intents in its `store/index.json`
6. The coordinator has the full picture and runs an auto team per intent as its main session
