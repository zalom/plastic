# Drive a graph from any harness

Plastic holds an intent's work graph and tells a driver what to run next. The driver is any
program that can run `plastic` commands and start a model: a shell script, Claude Code in print
mode, Codex in `exec` mode, or an agent built on an SDK. Plastic starts no model itself. This page
shows the loop a driver runs.

## The loop

1. Run `plastic graph ready ID --json`. Its `result.nodes` lists the nodes that are ready. Each is
   `{id, title, kind, criterion, state, needs}`. Stop when the list is empty.
2. For each ready node, run `plastic node claim ID NODE --json`. The answer carries
   `result.packet`, the brief for the worker.
3. Start the worker with the packet. It does the work.
4. Record the result with `plastic node done ID NODE TEXT --output PATH`, or with
   `plastic node fail`, `plastic node ask` or `plastic node impede` when the worker could not
   finish. Go back to step 1.

Two or more ready nodes have no edge between them, so a driver may work them at the same time.

## The packet

`result.packet` holds everything a worker needs, so it reads no other file to start.

| Key | Holds |
| --- | ----- |
| `node` | `{id, title, kind, state}` of the claimed node. |
| `criterion` | `{key, text}` of the done criterion the node serves. |
| `input` | The input the planner wrote on the node. |
| `needs` | One `{id, title, output}` for each node this one needs. `output` is the parsed JSON that node stored, or `null` when it stored none. |
| `schema` | The absolute path of `resources/tmp/schemas/NODE.json` in the intent folder, or `null` when no such file exists. |

The text claim prints the same facts as lines: `node:`, `criterion:`, `criterion text:`, `input:`,
`needs:` and `schema:`.

## Keep the output of a node

`plastic node done ID NODE TEXT --output PATH` stores the JSON in the file at PATH as the node's
output. TEXT is still required, because it is the node's findings. Plastic refuses output that is
not JSON: the call exits 1, stores nothing and leaves the node claimed, so the driver can finish
it again or fail it. A node that needs this one reads the output at `result.packet.needs[].output`.

Three things are called output, so keep them apart:

| Where | What it is |
| ----- | ---------- |
| The node's `output` column | The JSON text that `--output` stored. It syncs up and down byte for byte. |
| `result.packet.needs[].output` | That text, parsed, in the packet of a node that needs this one. |
| `result.output` of a `--json` answer | The text lines the command printed. It has nothing to do with a node. |

## Check the output against a schema

Plastic does not check JSON against a schema. The harness does. To give a node a schema, write it
to `resources/tmp/schemas/NODE.json` in the intent folder, for example `n3.json`. The claim names
that path in `result.packet.schema`, and the driver passes the file to the harness:

- Claude Code: `claude -p PROMPT --output-format json --json-schema SCHEMA`, where SCHEMA is the
  schema text.
- Codex: `codex exec PROMPT --output-schema FILE --output-last-message OUT`.

`plastic graph check ID` reports a schema file that names no live node, and offers
`plastic graph show ID` to find the node. `plastic resources sort` leaves the files of
`resources/tmp/schemas/` where they are.

## Sessions and claims

- Set `PLASTIC_SESSION` to a name for the driver. `plastic node claim` fails without a session,
  and the claim holds the name of the session that took it.
- A claim lapses after 900 seconds without a renewal. A worker that runs longer renews it with
  `plastic node renew ID NODE`.
- Exit code 3 means Plastic refused the call, for example when another session took a lapsed
  claim. Stop that node and do not retry with other options.
- After three runs of one node, the next claim moves it to `needs_info` with a question for the
  owner. The driver stops that node.
- Run one driver for each intent. Two drivers on one intent claim nodes against each other.

## Build it on an SDK

The loop does not change with the SDK. Each worker step is a call the SDK makes with the packet as
its prompt, and the SDK's own pages say how.

- Claude Agent SDK: <https://docs.claude.com/en/api/agent-sdk/overview>, read 2026-11-22.
- OpenAI Agents SDK: <https://openai.github.io/openai-agents-python/>, read 2026-11-22.
