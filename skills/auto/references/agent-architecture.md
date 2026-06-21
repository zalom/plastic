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
- Spin up an enforcer-led team to deliver an intent
- Contribute back to the Main Orchestrator when new intents are born
  that could enrich the Main Knowledge Base

## The Auto-Mode Team

Auto mode spins up exactly ONE enforcer-led team per intent. The plastic-enforcer
IS the auto orchestrator itself, not a separately dispatched agent. Making the
orchestrator the enforcer avoids the who-gates-the-gater regress (the gate-keeper
can never be ungated).

The team has five roles, one per place in the What, Why, How, Exec cycle:

- **plastic-brainstorming** (Why exploration): enriches `## Context` and records
  `### Decisions` with rationale.
- **plastic-spec-specialist** (Why-to-How boundary): consolidates the Why into
  `spec.md` (Problem, Goals, Non-Goals, Approach, Decisions, Acceptance Criteria).
- **plastic-planner** (How): produces `plan.md`, `actions/ACTION_N.md`, and
  `checklist.md`.
- **plastic-executor** (Exec): writes the code, checks off `checklist.md`, appends
  `## Insights`, and drives the suite green.
- **plastic-enforcer** (spans the whole cycle): orchestrates and gates.

### Handoff Contracts

Each specialist receives the prior stage's deliverable and produces the next stage's
input. The enforcer dispatches one specialist per stage with a constructed context
bundle, gates that deliverable against the stage's exit criteria, and only then hands
off to the next stage. Dispatch is sequential on a single branch, because the stage
deliverables share files (a parked spec, plan, and checklist all live in the same
intent directory).

The chain: intent `## Intent` / `## Context`, then enriched `## Context` plus
`### Decisions`, then `spec.md`, then `plan.md` plus `actions/` plus `checklist.md`,
then the code changes plus a checked-off checklist plus `## Insights`.

### Spawn Preamble (L2 live-state injection)

Every dispatched specialist is booted with a spawn preamble: the enforcer runs
`scripts/spawn-preamble <intent_dir> --role <role>` and prepends its output to the
specialist's prompt. The preamble is a pure function of the intent directory on disk
(no network, no clock, no randomness), so it is deterministic and rebuildable. It
carries the active intent id and intent line, the current lifecycle stage (the last
savepoint line, else stage derived from which lifecycle files exist), the cycle
role, and the honoring instruction that the agent must emit valid lifecycle artifacts
and not hallucinate intents or stages. This is the standard L2 live-state mechanism
for harnesses whose spawned sub-agents do not inherit the top-level session event. See
`docs/reference/harness-adapters.md` for how it slots into the per-harness contract.

### Completion Reports

Every dispatched specialist ends its turn with a structured completion report as its final
message (its return value), so the agent that did the work is the one that accounts for it. The
report carries a common envelope plus a role-specific payload that fulfils the agent's place in
the cycle; the planner explains the plan back to the orchestrator, the executor reports what was
built and the test result, and so on. The format lives in `references/agent-report-contract.md`,
and the verbatim instruction is injected once via the spawn preamble's `REPORT_CONTRACT`
constant, which the role prompts reproduce.

Enforcement is require-report then synthesize-fallback. The preamble and prompts make the report
mandatory (decision-shaping), but child-agent honor is best-effort across harnesses (Tier B/C),
so it is never a hard block. When a specialist returns no usable report, the enforcer runs
`scripts/agent-report <intent_dir> --role <role>`, a pure function of the intent dir (no network,
clock, or randomness, mirroring `spawn-preamble`) that emits a filesystem-derived report from the
savepoint, the artifacts present, the checklist checked/total, and the outcome line. A handoff
account therefore always exists: agent-authored when present, deterministically reconstructed
otherwise. This structures the finish notification only; in-flight observations stay in
`## Insights`, no progress chatter is added.

### Gate Ownership

The enforcer arms and verifies the lifecycle gate, then gates every stage transition.
It never delegates gate ownership. At the final gate only, it dispatches an
INDEPENDENT reviewer subagent to review the delivered work. That reviewer is not a
permanent sixth role, it exists only for the final review.

### Headless Manual Gate

When running headless or in the background, the enforcer enforces gates manually and
does not rely on hooks, because `CLAUDE_SESSION_ID` may be unset in those runs (the
gate-check and savepoint hooks no-op without it). The enforcer arms via the bridge's
derived-key fallback and verifies state itself.

### Delegation

The roles are thin handoff contracts, not a spawning engine. Dispatch and review run
by default through Plastic's own engine, `plastic-executing-plan` (implementer plus
two-stage review, no external plugin). When `superpowers:subagent-driven-development`
and `superpowers:dispatching-parallel-agents` are available, or the user asks for them,
they delegate to those as an enhancement. The team model defines who hands what to whom
and where the gates sit; the dispatch engine, native or superpowers, does the actual
spawning.

### Fallback by Case

The default is always Plastic's native engine, so a user without superpowers still gets
the full behavior. If the harness supports subagents but superpowers is absent, auto
mode dispatches through `plastic-executing-plan`. If the harness has no subagent dispatch
at all, auto mode falls back to a single agent walking the full What, Why, How, Exec
cycle itself. The enforcer's gate discipline still applies in every case.

### Dogfood Proof

Intents 60, 61, and 62 were delivered by exactly this enforcer-led team on a shared
branch, which is the dogfooded proof that the model works end to end.

## Two Modes

- **Human-driven:** Human chats with the Main Orchestrator, creates intents,
  brainstorms, then the Main Orchestrator dispatches Project Orchestrators and teams
  for execution.
- **Autonomous:** Human gives the Main Orchestrator a starting intent with defined
  outcomes. The enforcer-led team runs the full cycle (the specialists do the
  lifecycle, the enforcer reviews Insights and gates), then the orchestrator spawns
  next intents and dispatches again.

## Autonomous Delivery

Human owns What and Why for human-initiated intents. The team assists (research,
exploration) but the human drives until handoff. When Why is complete, or the human
triggers `plastic-auto`, the enforcer-led team takes over How and Exec autonomously.

- **Safe-by-default:** the executor always prefers non-destructive routes (rename vs
  delete, additive migrations, backups before changes). Destructive actions on
  existing projects require human approval unless `--skip-permissions` is set.
- **Notification only on:** finish or hard stop (blocked on destructive action,
  unresolvable error). No progress reports, `## Insights` tracks everything.
- **Greenfield autonomy:** during initial project creation, all decisions are
  non-destructive (nothing to destroy), so the team has full autonomy for greenfield
  choices.
- **Autonomous decisions** are logged in `## Insights` with the `(autonomous)` marker.

## Coordinator Loop

When "work on Project X":
1. Read `projects.yml`, find the project path
2. Load global config (defaults)
3. Load project config (overrides)
4. Load global INDEX.md, find hub intents tagged `project-<name>`
5. Load project INDEX.md, find tactical intents
6. The coordinator has the full picture, spins up an enforcer-led team per intent
