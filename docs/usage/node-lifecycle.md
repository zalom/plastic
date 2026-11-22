# The node lifecycle

![How a node moves through its states. node add writes an open node. The main session claims it with node claim as it dispatches the agent, and the claim names the session that holds it. node done records the judged report. node fail, node ask and node impede stop the node, and node release or node resolve reopens it. node remove takes an open node out of the graph.](../contributing/figures/node-lifecycle.svg)

A node is one unit of work in an intent's work graph. Only the main session, the session the
person talks to, moves a node. The agents it dispatches do the work and report back.

| State | How a node gets there | What moves it on |
| ----- | --------------------- | ---------------- |
| `open` | `plastic node add ID TITLE --criterion KEY` | `plastic node claim`, `plastic node remove` |
| `claimed` | `plastic node claim ID NODE` | `plastic node done`, `plastic node fail`, `plastic node ask`, `plastic node impede`, `plastic node release` |
| `done` | `plastic node done ID NODE TEXT` | Nothing. The node is finished. |
| `failed` | `plastic node fail ID NODE TEXT` | `plastic node release` |
| `needs_info` | `plastic node ask ID NODE TEXT` | `plastic node resolve` |
| `impeded` | `plastic node impede ID NODE TEXT` | `plastic node resolve` |
| `removed` | `plastic node remove ID NODE` | Nothing. The node has left the graph. |

## Added

`plastic node add` writes an `open` node, keyed to one done criterion of `spec.md`.
`plastic edge add ID FROM TO` says that one node needs another. A node is ready when every node
it needs is done, and `plastic graph ready ID` lists the ready nodes. Only an `open` node can be
removed.

## Claimed

The main session runs `plastic node claim ID NODE` as it dispatches the agent for that node. The
claim names the main session and prints the node's brief, which the main session hands to the
agent. A claim in an intent that is not in progress is refused with exit 3 and offers
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

Each claim opens one run of the node, and each move out of `claimed` closes it with the move's
result. `plastic graph show ID` names the holder of each claimed node and its runs.
