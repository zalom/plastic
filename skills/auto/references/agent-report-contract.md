# Agent Completion Report Contract

Every agent dispatched by the auto-mode enforcer MUST end its turn with a structured
completion report. This doc defines that report: one common envelope plus a per-role payload.
It is the format the `REPORT_CONTRACT` constant in `scripts/spawn-preamble` points at, the
role prompts (`agents/plastic-*.md`) reproduce, and the deterministic fallback
(`scripts/agent-report`) approximates. Keep all four in agreement; the constant in
`scripts/spawn-preamble` is the single source of truth for the injected wording.

## Purpose

The report is the agent's FINAL MESSAGE (its return value), not a side-channel file. Every
harness hands a spawned agent's final text back to the dispatcher, so the final message is the
one carrier that works everywhere (decision D1). The report structures the FINISH notification
only. In-flight observations still go in `## Insights`; the report does not add progress chatter
(decision D5). An agent that finishes correct artifacts but goes idle without a report has not
completed its handoff: the agent that did the work is the cheapest, most accurate source of the
account.

## Prose-stripped (intent 84)

The report is the envelope and the per-role payload, nothing else. Dispatched and background
subagents report and do their job; they do not narrate. Strip conversational prose: no
greeting, no preamble, no "Here is what I did" framing, no end-recap, no restating of the task.
Reasoning belongs in the thinking channel, not the report body. This tightens the FORM (the
fields stay exactly as below); it does not remove any required field.

## Common envelope

Every role report, whatever the stage, carries these fields:

- **Role**: which specialist produced this (brainstorming, spec, planner, executor, reviewer).
- **Intent id and stage**: the active intent id and the cycle stage just completed.
- **Status**: `delivered` or `blocked`.
- **Artifacts written**: the files produced or changed (store paths, and project paths for the
  executor).
- **Verification / tests run**: the command run and its result, or `n/a` for stages that write
  no code.
- **Checklist deltas**: which checklist items this turn checked off (executor), or `n/a`.
- **Deviations from spec**: anything done differently from the spec or plan, and why, or `none`.
- **Blockers / handoff notes**: what the next stage must watch for, or `none`.

## Per-role payload

Each role appends a payload that fulfils its place in the What, Why, How, Exec cycle (decision
D2). The payload is what makes the report useful to the orchestrator beyond the envelope.

### brainstorming (Why exploration)
- Decisions recorded in `### Decisions`, each with its one-line rationale.
- Context enriched: what was researched and the key findings.
- Open questions resolved, and any deliberately left for the spec.

### spec-specialist (Why to How boundary)
- Spec sections produced (Problem, Goals, Non-Goals, Approach, Decisions, Acceptance Criteria).
- How the recorded decisions resolved into the chosen approach.
- Acceptance-criteria count, so the planner knows the surface to cover.

### planner (How): worked exemplar
The planner report EXPLAINS THE PLAN BACK TO THE ORCHESTRATOR. It carries:
- The ordered actions, one line each: what the action does and how it is verified.
- Decomposition rationale: why this order, and why the actions are independent.
- Checklist coverage: item count and that every action plus suite-green is covered.
This is the exemplar because the plan is an argument, and the orchestrator gates on whether that
argument is sound before any code is written.

### executor (Exec)
- Actions implemented this turn, mapped to checklist items checked off (checked / total).
- A summary of the code changed (files and the shape of the change).
- Test result: the full-suite command and its pass / fail counts.
- Insights appended, with the `(autonomous)` marker.

### final reviewer (final gate)
- Verdict: `pass` or `blockers found`.
- Each acceptance criterion checked, with the evidence that confirms or refutes it.
- Gaps or risks found, ranked, with a recommended disposition.

## Fallback: always a report

Decision-shaping (the preamble plus these prompts) makes the report mandatory, but child-agent
honor is best-effort across harnesses (Tier B/C in `docs/reference/harness-adapters.md`), so the
contract is never a hard block (decision D3). When a dispatched agent returns no usable report
(it went idle, emitted only a bare ping, or its message was lost to a mid-run interjection), the
enforcer synthesizes one:

```
scripts/agent-report <intent_dir> --role <role>
```

`scripts/agent-report` is a pure function of the intent directory (no network, clock, or
randomness, mirroring `scripts/spawn-preamble`): it reads the current stage from the savepoint
ledger, the lifecycle artifacts present, the checklist checked / total, and the `## Outcome`
line, and emits a filesystem-derived report labelled `synthesized`. So a handoff account always
exists: authored by the agent when possible, reconstructed deterministically when not. This
formalizes the by-hand reconstruction the orchestrator did while delivering intent 68.
