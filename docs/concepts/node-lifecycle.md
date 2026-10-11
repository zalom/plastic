# The node lifecycle

![How a node moves through its states. node add writes an open node. The main session claims it with node claim as it dispatches the agent, and the claim keeps the delivery lock live. node done records the judged report. node fail, node ask and node impede stop the node, and node release or node resolve reopens it. node remove takes an open node out of the graph.](../contributing/figures/node-lifecycle.svg)

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
agent. A node that waits on another node is refused. After three claims, the next claim moves the
node to `needs_info` with a standing question, and the owner decides.

## Done

The agent ends with its report. The main session judges the report and records it with
`plastic node done ID NODE TEXT`, where the text is the node's findings. A report that names a
failure, a question or an impediment goes in with `plastic node fail`, `plastic node ask` or
`plastic node impede` instead. `plastic node release` sets a claimed or failed node back to
`open`, and `plastic node resolve` reopens a `needs_info` or `impeded` node with its answer.

## How a claim keeps the lock live

`plastic auto ID` takes the delivery lock: one row of `local.db` that names the session that
delivers the intent. The lock is live while the session runs and one of these holds:

- The stop hook renewed the lock within the last 1800 seconds.
- The session holds a node of the intent that it claimed within the last 7200 seconds.

A dispatched agent can work for a long time while the main session takes no turns, so the stop
hook does not renew the lock. The claim keeps the lock live until the agent reports, for up to
two hours. Run `plastic intent lock status ID` to see who holds the lock and why it is live.
