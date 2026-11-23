# Drive a graph from any harness

Plastic holds an intent's work graph and tells a driver what to run next. The driver is any
program that can run `plastic` commands and start a model: a shell script, Claude Code in print
mode, Codex in `exec` mode, or an agent built on an SDK. Plastic starts no model itself. This page
shows the loop a driver runs.

## The driver role

When the driver is the open Claude Code or Codex session, `plastic install` writes the role
`plastic-driver` for it, next to the planner, executor and retriever roles. The role tells the session to run
the loop below: start one subagent or background worker for each ready node, of the role that fits
the node's kind, and hand it the intent id and the node id. The driver picks the `--agent` name of each worker and hands it over with the ids. The worker claims its node, which
prints the claim packet, and finishes it itself. The driver waits for the harness's notice that a worker ended, then reads
`plastic graph ready ID --json` again; it does not poll in a loop.

| Node kind | Worker |
| --------- | ------ |
| `orchestrator` | The planner role, `plastic-planner`. |
| `work` | The executor role, `plastic-executor`. |
| `retrieval` | The read-only retriever role, `plastic-retriever`. |

The worker finishes with `plastic node done ID NODE TEXT --output PATH`, where PATH is a JSON file (Plastic refuses other output; the claim packet says so), so the next node reads its
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

`plastic graph ready ID --json` also carries `result.repairs`: one entry for each node that failed
or waits on the owner (`failed`, `needs_info` or `impeded`), with `id`, `title`, `state` and the
not-done nodes `downstream` of it through needs edges, transitively. It is empty when nothing
stopped. The ready list keeps meaning the nodes that can be claimed now, so the loop stops only when
the ready list and `result.repairs` are both empty. A `failed` node is retried with
`plastic node release ID NODE`, or its region is re-planned with `plastic node add`,
`plastic edge add`, `plastic edge remove` and `plastic node remove`. A `needs_info` or `impeded` node
goes to the owner, who answers it with `plastic node resolve`; the driver re-plans after that.

Two or more ready nodes have no edge between them, so a driver may work them at the same time.

`plastic intent end` releases the driver claim of the intent in the step that closes it and prints
`driver claim: released, held by session S`. A closed intent has no live driver left.

## The packet

`result.packet` holds everything a worker needs, so it reads no other file to start.

| Key | Holds |
| --- | ----- |
| `node` | `{id, title, kind, state}` of the claimed node. |
| `criterion` | `{key, text}` of the done criterion the node serves. |
| `inputs` | The input paths the planner wrote on the node, in the order given; `[]` when it has none. |
| `needs` | One `{id, title, output}` for each node this one needs. `output` is the parsed JSON that node stored, or `null` when it stored none. |
| `rulings` | The intent's rulings in force as `{id, text}`, the newest 20, with superseded rulings left out. |
| `constraints` | The bullets under the spec's `## Constraints` heading, the first 20. |
| `omitted` | How many `rulings` or `constraints` the lists left out; `{}` when none. |
| `schema` | The absolute path of `resources/tmp/schemas/NODE.json` in the intent folder, or `null` when no such file exists. |

The text claim prints the same facts as lines: `node:`, `criterion:`, `criterion text:`, one `input:`
line for each input path, `needs:`, `ruling:`, `constraint:`, `omitted:` and `schema:`.

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
- A node added with `--deadline MINUTES` is overdue once its claim has run longer than that. `plastic graph
  ready ID --json` lists it under `result.overdue` with `id`, `title`, `claimed_by`, `claimed_minutes` and
  `deadline`. Plastic moves no node for it: the driver checks on the worker, and the owner decides
  whether to release the node.
- Exit code 3 means Plastic refused the call, for example when another session took a lapsed
  claim. Stop that node and do not retry with other options.
- After three runs of one node, the next claim moves it to `needs_info` with a question for the
  owner. The driver stops that node.
- Run one driver for each intent. `plastic intent start` and `plastic intent auto` take a driver claim for the session, which lapses after 15 minutes without a renewal. A second session is refused with exit 3 and the name of the driver, unless it passes `--take-over REASON`.

## Run a worker on a local model

A worker can run on a small model served on the same machine. Plastic starts no model and makes no
model call: it stores the model of each role and prints it, and the driver or the harness starts the
worker. Both harnesses keep their own run records, so the run figures come from them as before.

### Choose the model of a role

The model of a role is the setting `agents.models.ROLE`. Set it for one harness, named `claude-code`,
`codex` or `hermes`, then reinstall so the role file carries it:

```
plastic config set agents.models.plastic-executor qwen3-coder:30b --harness claude-code
plastic config set agents.models.plastic-executor gpt-oss:20b --harness codex
plastic install --reinstall
```

A value that is not one of the tier aliases `opus`, `sonnet` and `haiku` is written as it stands: into
the `model:` line of the Claude Code role file and the `model` field of the Codex role file. The model
name is the name the local server lists, for example in `ollama list`. A driver that starts workers
itself, as below, passes the same name on the command line.

### Claude Code on a local Ollama server

Ollama serves the Anthropic Messages API, so Claude Code needs only a base URL, a token Ollama ignores,
and the model name. Checked on 24 November 2026 against the
[Ollama page for Claude Code](https://docs.ollama.com/integrations/claude-code) and the
[Ollama Anthropic compatibility page](https://docs.ollama.com/api/anthropic-compatibility):

```
ANTHROPIC_BASE_URL=http://localhost:11434 ANTHROPIC_AUTH_TOKEN=ollama ANTHROPIC_API_KEY="" \
  claude -p "$PACKET" --model qwen3-coder:30b --output-format json
```

- Claude Code asks for its Sonnet, Haiku and Opus tiers for some steps. To send all of them to the local
  model, set `ANTHROPIC_DEFAULT_SONNET_MODEL`, `ANTHROPIC_DEFAULT_HAIKU_MODEL` and
  `ANTHROPIC_DEFAULT_OPUS_MODEL` to the same name.
- The model must support tool calling. Ollama refuses one that does not, for example `deepseek-r1:8b`
  answers "does not support tools".
- Give the server a context of 64k tokens or more, as the Ollama pages for Claude Code and Codex say, for
  example `OLLAMA_CONTEXT_LENGTH=65536` when starting `ollama serve`. A small window is the usual failure,
  because the claim packet and the role text are long.
- Claude Code does not fall back to the Anthropic cloud when the server does not answer; the call fails.

### Codex on a local Ollama server

Codex runs a local model with `--oss`. Checked with `codex exec --help` on 24 November 2026, and against
the [Ollama page for Codex](https://docs.ollama.com/integrations/codex):

```
codex exec --oss --local-provider ollama -m gpt-oss:20b "$PACKET"
```

- `--local-provider` takes `ollama` or `lmstudio`. Without it, and with no default set, Codex 0.171.0 stops with
  "No default OSS provider configured. Use --local-provider=provider or set oss_provider to one of: lmstudio,
  ollama in config.toml". To set a default, put `oss_provider = "ollama"` in `~/.codex/config.toml`.
- `codex exec` refuses to run outside a git repository; add `--skip-git-repo-check` for a worker that runs elsewhere.
- The model must support tool calling and the server needs a context of 64k tokens or more, as for Claude Code.
- The flag chooses the server. The model comes from `-m`, or from the `model` field of the role file when
  the worker is a Codex subagent.
- Ollama must be a version that the installed Codex supports; update both when `--oss` is refused.

### How a node reaches a local worker

1. The driver runs `plastic graph ready ID --json` and takes a ready node. The node kind picks the role:
   `work` goes to `plastic-executor`, `orchestrator` to `plastic-planner` and `retrieval` to
   `plastic-retriever`. The setting `agents.models.ROLE` of that role names the local model.
2. The driver runs `plastic node claim ID NODE --agent NAME --json`. The packet is `result.packet`.
3. The driver starts the worker as its own process with the command of its harness above, the model of
   the role and the packet as the prompt.
4. The worker, or the driver for it, records the result with `plastic node done ID NODE TEXT --output PATH`.

The role file carries only the model name, no base URL. A subagent that a cloud session starts therefore
uses the endpoint of its parent session. To run on the local server, start the worker as its own
`claude -p` or `codex exec` process with the environment above.

The run record shows no cost for such a run: `claude -p` against Ollama reports `total_cost_usd` as 0.
Tokens and timing still come from the harness's own record.

### What stays the same

The loop, the claim packet, `plastic node done ID NODE TEXT --output PATH` and the schema check do not
change. A small model may not follow the packet, so give a node a schema (see above) and read a refused
output as a failed attempt: `plastic node fail ID NODE TEXT`.

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
