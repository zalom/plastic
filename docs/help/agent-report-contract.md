# Agent completion report contract

Every agent the main session dispatches in auto mode MUST end its turn with a structured
completion report. This doc defines that report: one common envelope plus a per-role payload.
The role prompts (`agents/plastic-*.md`) reproduce it. The report is the only thing a
dispatched agent hands back: it writes no Plastic state, and the main session records the
result from the report.

## Purpose

The report is the agent's FINAL MESSAGE (its return value), not a side-channel file. Every
harness hands a spawned agent's final text back to the dispatcher, so the final message is the
one carrier that works everywhere. The report structures the FINISH notification
only. Observations go in its `insights:` field; the report does not add progress chatter.
An agent that finishes correct artifacts but goes idle without a report has not
completed its handoff: the agent that did the work is the cheapest, most accurate source of the
account.

## Prose-stripped

The report is the envelope and the per-role payload, nothing else. Dispatched and background
subagents report and do their job; they do not narrate. Strip conversational prose: no
greeting, no preamble, no "Here is what I did" framing, no end-recap, no restating of the task.
Reasoning belongs in the thinking channel, not the report body. This tightens the FORM (the
fields stay exactly as below); it does not remove any required field.

## Common envelope

Every role report, whatever the stage, carries these fields:

- **Role**: which agent produced this (planner, executor, plan reviewer, post-execution reviewer).
- **Intent id and stage**: the active intent id and the cycle stage just completed.
- **Status**: `delivered` or `blocked`.
- **Artifacts written**: the files produced or changed (store paths, and project paths for the
  executor).
- **Verification / tests run**: the command run and its result, or `n/a` for stages that write
  no code.
- **Nodes**: the work nodes this turn finished, each with its commit (executor), or `n/a`.
- **Deviations from spec**: anything done differently from the spec or plan, and why, or `none`.
- **Blockers / handoff notes**: what the next stage must watch for, or `none`.
- **Insights**: 0..N durable nuggets discovered this turn (the most interesting residue),
  each one a `## Insights`-worthy line; `none` if there were none. Background and dispatched
  agents MUST populate this: they carry each nugget home in the report and the main session
  records it (see Insights delivery below).

## Per-role payload

Multi-item payload fields (ordered actions, insights, nodes) default to tables;
single fields stay prose.

Each role appends a payload that fulfils its place in the What, Why, How, Exec cycle.
The payload is what makes the report useful to the main session beyond the envelope.

The main session dispatches four roles: the planner, the plan reviewer, the executor, and the
post-execution reviewer. The plan reviewer returns the shape in `plastic help
plan-reviewer-prompt`; the other three carry the payloads below.

### planner (How)
- The spec text, the action with its failure-mode matrix, and the proposed work nodes, each
  with the done criterion key it proves and the nodes it needs.
- Every ambiguity, impediment and newly found issue, each with what was tried.

### executor (Exec)
- The nodes landed this turn, each with its commit and its findings.
- A summary of the code changed (files and the shape of the change).
- Test result: the red commit's failing count, then the gate command and its pass / fail counts.
- Insights reported in the `insights:` field, each with the `(autonomous)` marker.

### post-execution reviewer
- Verdict: `pass` or `blockers found`.
- Each acceptance criterion checked, with the evidence that confirms or refutes it.
- Gaps or risks found, ranked, with a recommended disposition.
- Insights: durable discoveries from the review, reported in the `insights:` field.

## Fallback: always a report

These prompts make the report mandatory, but a dispatched agent honors them on a best effort,
so the contract is never a hard block. When a dispatched agent returns no usable report
(it went idle, emitted only a bare ping, or its message was lost to a mid-run interjection), the
main session reads the account from the disk instead: the commits on the intent branch, the
diff, and the test result. It records the node with `plastic node done ID NODE TEXT` when that
account proves the node, and with `plastic node fail ID NODE TEXT` when it does not.

## Insights delivery

Insights ride home in the completion report. Every agent reports its durable nuggets in the
`insights:` field, and the main session records each one on receipt with
`plastic intent note ID TEXT`. A dispatched agent never writes the intent file, so an insight
does not depend on the agent having write access to the store.

