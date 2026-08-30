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
- Lead an auto team to deliver an intent
- Contribute back to the Main Orchestrator when new intents are born
  that could enrich the Main Knowledge Base

## The Auto-Mode Team

Auto mode runs exactly ONE team per intent, led by the orchestrating session itself: the
plastic-enforcer IS the lead, not a separately dispatched agent. The team has two standing
roles plus two reviewer prompts dispatched as fresh agents (the four stage agents were removed
in 2.0, intent 304; the lead writes the Why and How record itself):

- **plastic-enforcer** (the lead, spans the whole cycle): takes the intent, writes `spec.md`,
  `plan.md`, the action files with their failure-mode matrix, and `checklist.md`; has the plan
  reviewed before code; dispatches the executor; applies the risk rule; closes.
- **plastic-executor** (Exec): commits the matrix's tests red, writes the code, checks off
  `checklist.md`, appends `## Insights`, and drives the suite green.
- **the plan reviewer**: a fresh agent on `plastic-intent-executing`'s
  `plan-reviewer-prompt.md`, dispatched once before any code exists.
- **the post-execution reviewer**: a fresh agent on `code-quality-reviewer-prompt.md`,
  dispatched only when the auto skill's risk rule fires; never the maker.

Two agent boots is the normal delivery (the plan reviewer, the executor); the post-execution
reviewer is the third only when risk calls for it.

### Handoff Contracts

The lead hands the executor one constructed context bundle: the spec decisions, the plan, the
action files with their matrix, the checklist, and the worktree path. The executor hands back
the code, the red and green commits, a checked-off checklist, `## Insights`, and its completion
report. Dispatch is sequential on a single branch, because the deliverables share files.

The chain: intent `## Intent` / `## Context`, then enriched `## Context` plus `### Decisions`,
then `spec.md`, then `plan.md` plus `actions/` plus `checklist.md`, then the plan review, then
the code changes plus a checked-off checklist plus `## Insights`.

### Spawn Preamble (L2 live-state injection)

Every dispatched agent is booted with a spawn preamble: the lead runs
`scripts/spawn-preamble <intent_dir> --role <role>` and prepends its output to the agent's
prompt. The preamble is a pure function of the intent directory on disk (no network, no clock,
no randomness), so it is deterministic and rebuildable. It carries the active intent id and
intent line, the current lifecycle stage (the last savepoint line, else the stage derived from
which lifecycle files exist), the cycle role, and the honoring instruction that the agent must
emit valid lifecycle artifacts and not hallucinate intents or stages. This is the standard L2
live-state mechanism for harnesses whose spawned sub-agents do not inherit the top-level
session event. See [`harness-adapters.md`](https://github.com/zalom/plastic/blob/main/docs/reference/harness-adapters.md) for how it slots into the per-harness contract.

### Completion Reports

Every dispatched agent ends its turn with a structured completion report as its final message
(its return value), so the agent that did the work is the one that accounts for it. The report
carries a common envelope plus a role-specific payload that fulfils the agent's place in the
cycle; the executor reports what was built and the test result, a reviewer reports its verdict
and findings. The format lives in `references/agent-report-contract.md`, and the verbatim
instruction is injected once via the spawn preamble's `REPORT_CONTRACT` constant, which the
role prompts reproduce.

Enforcement is require-report then synthesize-fallback. The preamble and prompts make the report
mandatory (decision-shaping), but child-agent honor is best-effort across harnesses (Tier B/C),
so it is never a hard block. When an agent returns no usable report, the lead runs
`scripts/agent-report <intent_dir> --role <role>`, a pure function of the intent dir (no network,
clock, or randomness, mirroring `spawn-preamble`) that emits a filesystem-derived report from the
savepoint, the artifacts present, the checklist checked/total, and the outcome line. A handoff
account therefore always exists: agent-authored when present, deterministically reconstructed
otherwise. This structures the finish notification only; in-flight observations stay in
`## Insights`, no progress chatter is added.

Immediately after an agent returns and before the next handoff, the lead records the
delegate's activity through `plastic-lock delegate --intent-dir <intent-dir> --delegate <id>
--status finished|failed`. `finished` requires a usable agent-authored or synthesized completion
report. A blocked or errored return, or one with no report that can be synthesized, is `failed`
and stops the handoff under the normal error procedure. Activity status is descriptive and does
not revoke the registered delegate's authorization.

### Review Ownership

The lead owns every review decision: it dispatches the plan reviewer before code, folds the
findings itself, and decides from the risk rule whether the post-execution reviewer runs. It
never delegates that decision, and neither reviewer is ever the maker of what it reviews.
Nothing blocks a write in 2.0 (the gate hooks were removed, intent 302); the lock, the
worktree, and the record are how the team keeps one delivery in one place.

### The risk list

The post-execution reviewer runs when the executor's diff touches any of these paths, or when
the auto skill's other two risk clauses fire:

- `hooks/`, `scripts/hook-*`, `scripts/lib/hook_registry.rb`
- `scripts/lib/lock.rb`, `scripts/lib/arm.rb`, `scripts/plastic-lock`, `scripts/end-intent`
- `scripts/lib/installer_core.rb`, `scripts/install*`, `scripts/update.rb`
- `package.json`, `.claude-plugin/*.json`, `CHANGELOG.md`

Grow this list here, not in the skill body.

### Headless Note

In a headless or background run the session id may be unset. `plastic-lock arm` then keys the
lock by a derived session key, the record hook still writes the savepoint ledger from the
written path, and the lead verifies state from the files (`plastic-lock status`,
`savepoint.md`, the diff) rather than from a hook it assumes fired.

### Delegation

The roles are thin handoff contracts, not a spawning engine. Dispatch runs through Plastic's
own engine, `plastic-intent-executing`: one executor for the consolidated action, the two
reviewer prompts as fresh agents. The team model defines who hands what to whom and where the
reviews sit; the engine does the actual spawning.

### Fallback by Case

If the harness supports agent dispatch, auto mode dispatches through
`plastic-intent-executing`. If the harness has no agent dispatch at all (Codex CLI today), the
lead walks the five steps itself: it still writes the matrix and the tests first, and reviews
its own plan against the matrix before code, saying so in `## Insights`.

### Dogfood Proof

Intents 60, 61, and 62 were delivered by the enforcer-led team on a shared branch, and the
simplify-plastic roadmap's batch 2 (intents 302 to 306) was delivered in the ruled two-boot
shape: the lead wrote the matrix, one adversarial plan reviewer read it, the lead built inline
tests first, one suite run per intent.

## Two Modes

- **Human-driven:** Human chats with the Main Orchestrator, creates intents, thinks them
  through, then the Main Orchestrator dispatches Project Orchestrators and teams for execution.
- **Autonomous:** Human gives the Main Orchestrator a starting intent with defined outcomes.
  The auto team runs the full cycle, then the orchestrator spawns next intents and dispatches
  again.

## Autonomous Delivery

Human owns What and Why for human-initiated intents. The team assists (research, exploration)
but the human drives until handoff. When Why is complete, or the human triggers `plastic-auto`,
the auto team takes over How and Exec autonomously.

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
4. Load global INDEX.md, find hub intents tagged `project-<name>`
5. Load project INDEX.md, find tactical intents
6. The coordinator has the full picture, leads an auto team per intent

## Spawn preamble (intent 152)

`scripts/spawn-preamble` emits a live-state block purely from filesystem state: the active
intent, stage, role/cycle-step, the honor instruction, and the report contract. When the
intent's code worktree is resolvable and exists on disk, it also appends the worktree's
absolute path plus a verbatim instruction to `cd` there directly, for harnesses whose
`EnterWorktree` cannot discover a nested repo from a non-repo launch directory. Output is
byte-identical when no worktree resolves.
