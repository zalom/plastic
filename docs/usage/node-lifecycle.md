# The node lifecycle

![How a node moves through its states. node add writes an open node. The main session claims it with node claim as it dispatches the agent, and the claim names the session that holds it. node done records the judged report. node fail, node ask and node impede stop the node, and node release or node resolve reopens it. node remove takes an open node out of the graph.](../contributing/figures/node-lifecycle.svg)

A node is one unit of work in an intent's work graph. Only the main session, the session the
person talks to, moves a node. The agents it dispatches do the work and report back.

| State | How a node gets there | What moves it on |
| ----- | --------------------- | ---------------- |
| `open` | `plastic node add ID TITLE --criterion KEY` | `plastic node claim`, `plastic node remove` |
| `claimed` | `plastic node claim ID NODE --agent NAME` | `plastic node done`, `plastic node fail`, `plastic node ask`, `plastic node impede`, `plastic node release` |
| `done` | `plastic node done ID NODE TEXT` | Nothing. The node is finished. |
| `failed` | `plastic node fail ID NODE TEXT` | `plastic node release` |
| `needs_info` | `plastic node ask ID NODE TEXT` | `plastic node resolve` |
| `impeded` | `plastic node impede ID NODE TEXT` | `plastic node resolve` |
| `removed` | `plastic node remove ID NODE` | Nothing. The node has left the graph. |

## Added

`plastic node add` writes an `open` node, keyed to one done criterion of `spec.md`.
`plastic edge add ID FROM TO` says that one node needs another. A node is ready when every node
it needs is done, and `plastic graph ready ID` lists the ready nodes, and for a failed, needs_info or impeded node a `repair:` line naming the nodes that wait on it, the region to re-plan. Only an `open` node can be
removed.

After `plastic node done` the nodes that are now ready are named on `ready:` lines, and the `next:` line claims the first of them: `plastic node claim ID NODE --agent NAME`. When no node is ready, or the intent is complete, the `next:` line stays `plastic graph ready ID`.

A node can carry a deadline: `plastic node add ID TITLE --criterion KEY --deadline MINUTES` stores the
minutes a claim on it may run. The value is a whole number above 0; any other value exits 2 and adds
no node. `plastic graph show` prints it on the node line as `deadline 30 minutes`. A node without one
has none.

Work found while doing a node is added with `plastic node add ID TITLE --criterion KEY --found-in NODE`. The node must be in the same intent: a missing node exits 1 and a removed node exits 3, each naming it. The link is a `found_in` edge from the new node to the node it was found in: `plastic graph show` prints it as `found in NODE` on the new node, and it adds no need and changes no readiness.

## Claimed

The main session runs `plastic node claim ID NODE --agent NAME` as it dispatches the agent for that node. `--agent` is required: a claim without it exits 2 and names the flag. The
claim names the main session and prints the node's brief, which the main session hands to the
agent.

Each claim opens a run that also records the harness of the claiming session. When the run ends,
Plastic reads the model, the tokens and the cost of the work from the harness's own local record (Claude Code transcripts under `~/.claude/projects`, Codex logs under `~/.codex/sessions`), including the worker's own session when a subagent ran the claim. The run stores its start and its end in whole seconds, so the read takes in the whole second of each. Plastic starts nothing and calls no API. Claude Code writes its cost total about once per session, at the stop, so the cost is recorded only when the transcript holds a total after the run; a run in a live session records no cost and the note says so. When the record is missing or unreadable, the run keeps what is known and a note says what was not found; the claim and the done never fail for it. `plastic graph show ID` prints one `run:` line for each run, with when it started, when it ended and its length (`4m 12s`, `1h 2m 3s`, `under 1s` for a run shorter than a second), or `running` for a run with no end yet; `--json` carries them under `result.runs` as `started_at`, `ended_at` and `length_seconds`. A run written after the work stands out by its length. A claim in an intent that is not in progress is refused with exit 3 and offers
`plastic intent start ID`. A claim before the owner's go-ahead is refused with exit 3. A node that waits on another node is refused, also with exit 3. After three runs, the next claim moves the
node to `needs_info` with a standing question, and the owner decides.

## Done

The agent ends with its report. The main session judges the report and records it with
`plastic node done ID NODE TEXT`, where the text is the node's findings. A report that names a
failure, a question or an impediment goes in with `plastic node fail`, `plastic node ask` or
`plastic node impede` instead. `plastic node release` sets a claimed or failed node back to
`open`, and `plastic node resolve` reopens a `needs_info` or `impeded` node with its answer.

Each of `node done`, `node fail`, `node ask` and `node impede` takes `--file PATH`, repeated for
more than one file. The call reads the changed files of the intent folder, limited to the named
paths, in the same transaction as the move, so the node's result and the files it changed land
together. A call without `--file` reads every changed file of the folder.

## How a claim stays live

A claim names the session that holds the node. The session renews it, and a claim lapses after
900 seconds without a renewal. The session renews its claims at every `plastic` command it runs,
at the stop hook, and with `plastic node renew ID NODE`.

- Another session can take a lapsed claim with `plastic node claim`. The old run closes as
  `lapsed` and a new run opens.
- The old holder's next node command exits 3, names the new holder and changes nothing.
- A lapsed claim that nobody took still completes for its holder.

## When a claim runs past its deadline

A claimed node whose claim started more than its deadline ago is overdue. `plastic graph ready ID`
prints a line for each, such as `overdue: n3 Build claimed 42 minutes ago, deadline 30`, and `--json`
lists them under `result.overdue`. The minutes are rounded up, so a claim 30 minutes and 30 seconds
old on a 30-minute deadline reads `claimed 31 minutes ago`. The time is the time of the call. A node with no deadline is never
overdue. Plastic only reports it: the node stays claimed by its session, and the driver checks on the
worker. The lapse finds a worker that stopped renewing; the deadline finds a worker that still runs
but runs too long.

Each claim opens one run of the node, and each move out of `claimed` closes it with the move's
result. `plastic graph show ID` names the holder of each claimed node and its runs.
