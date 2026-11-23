# Drive a graph from any harness

Plastic holds an intent's work graph and tells a driver what to run next. The driver is any
program that can run `plastic` commands and start a model: a shell script, Claude Code in print
mode, Codex in `exec` mode, or an agent built on an SDK. Plastic starts no model itself. This page
shows the loop a driver runs.

## The driver role

When the driver is the open Claude Code or Codex session, `plastic install` writes the role
`plastic-driver` for it, next to the planner and executor roles. The role tells the session to run
the loop below: start one subagent or background worker for each ready node, of the role that fits
the node's kind, and hand it the intent id and the node id. The worker claims its node, which
prints the claim packet, and finishes it itself.

| Node kind | Worker |
| --------- | ------ |
| `orchestrator` | The planner role, `plastic-planner`. |
| `work` | The executor role, `plastic-executor`. |
| `retrieval` | A read-only worker that searches and reports. |

The worker finishes with `plastic node done ID NODE TEXT --output PATH`, so the next node reads its
output in its packet. At most 3 workers run at once. The setting `driver.max_workers` holds the
limit: change it with `plastic config set driver.max_workers N` and run `plastic install --reinstall`,
and the installed role prints the new number. When the harness cannot start workers, the session
works the nodes itself, one at a time. Plastic starts no worker.

## The loop

1. Run `plastic graph ready ID --json`. Its `result.nodes` lists the nodes that are ready. Each is
   `{id, title, kind, criterion, state, needs}`. Stop when the list is empty.
2. For each ready node, run `plastic node claim ID NODE --agent NAME --json`. The answer carries
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
| `rulings` | The intent's rulings in force as `{id, text}`, the newest 20, with superseded rulings left out. |
| `constraints` | The bullets under the spec's `## Constraints` heading, the first 20. |
| `omitted` | How many `rulings` or `constraints` the lists left out; `{}` when none. |
| `schema` | The absolute path of `resources/tmp/schemas/NODE.json` in the intent folder, or `null` when no such file exists. |

The text claim prints the same facts as lines: `node:`, `criterion:`, `criterion text:`, `input:`,
`needs:`, `ruling:`, `constraint:`, `omitted:` and `schema:`.

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

Checked with `claude --help` and `codex exec --help` on 22 November 2026:

- Claude Code: `claude -p PROMPT --output-format json --json-schema SCHEMA`, where SCHEMA is the
  schema text.
- Codex: `codex exec PROMPT --output-schema FILE --output-last-message OUT`.

`plastic graph check ID` reports a schema file that names no live node. It prints a `hand edit:` line
under each finding that no command repairs, a `repair:` line under each finding that one does, and no
`next:` line when only hand-edit findings remain. `plastic resources sort` leaves the files of
`resources/tmp/schemas/` where they are.

## Sessions and claims

- Give each driver its own `PLASTIC_SESSION`. The claim holds the name of the session that took it. When
  `PLASTIC_SESSION` is not set, Plastic uses the session of the harness, and then `terminal-` and the login
  at a terminal. Two drivers that share a name share a claim.
- A claim lapses after 900 seconds without a renewal. When a driver hands out nodes, each worker
  renews its own claim with `plastic node renew ID NODE`, for example every five minutes, while it runs.
- Exit code 3 means Plastic refused the call, for example when another session took a lapsed
  claim. Stop that node and do not retry with other options.
- After three runs of one node, the next claim moves it to `needs_info` with a question for the
  owner. The driver stops that node.
- Run one driver for each intent. Two drivers on one intent claim nodes against each other.

## Build it on an SDK

The loop does not change with the SDK. Each worker step is a call the SDK makes with the packet as
its prompt. The two calls below are Python, written from the SDK pages read on 22 November 2026.

The Claude Agent SDK ([Python reference](https://code.claude.com/docs/en/agent-sdk/python), read 2026-11-22)
takes the output format from the schema in `output_format` and returns the answer in
`ResultMessage.structured_output`:

```python
from claude_agent_sdk import query, ClaudeAgentOptions, ResultMessage

options = ClaudeAgentOptions(output_format={"type": "json_schema", "schema": schema})
async for message in query(prompt=packet_json, options=options):
    if isinstance(message, ResultMessage):
        output = message.structured_output
```

The OpenAI Agents SDK ([Agents](https://openai.github.io/openai-agents-python/agents/) and
[Results](https://openai.github.io/openai-agents-python/results/), read 2026-11-22) takes the
output type on the agent, and `result.final_output` is an object of that type. The pages show a
Pydantic model as the type and do not show a JSON schema file, so the driver builds the model from the schema:

```python
from agents import Agent, Runner

agent = Agent(name="worker", instructions="Do the node", output_type=NodeOutput)
result = await Runner.run(agent, packet_json)
output = result.final_output
```

In both calls the driver writes the output to a file and passes it to `plastic node done ID NODE TEXT --output PATH`.
