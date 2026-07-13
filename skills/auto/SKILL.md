---
name: plastic-auto
description: >-
  Autonomous intent delivery - agent takes over How and Exec. Use when user says
  "auto", "take it from here", "deliver this", or when brainstorming-grill-me concludes
  and user confirms autonomous execution. Requires an active intent in INDEX.md.
user-invocable: true
---

# Auto - Autonomous Intent Delivery

Announce: "Taking over intent [ID] - [name] for autonomous delivery."

**Advisory (not a gate).** At auto-mode start, recommend once that the user run this
orchestrating main session on the best available thinking model (Fable, Opus, or whatever
supersedes them) for the sharpest gating and synthesis. This is advice only: it changes no
behavior and blocks nothing if ignored. It concerns the human's MAIN session; dispatched
subagents keep their pinned tier and never resolve to Fable, unless an explicit
`agents.models.<name>` config override names Fable for that role, in which case the override
is honored as written. The two advisors, `plastic-advisor` and `plastic-faux-advisor`, are not
lifecycle stage roles: the never-Fable rule governs stage agents only. Neither is ever
dispatched by the auto pipeline; they are consultation roles summoned deliberately by the user
or the main session, and their models are user configuration (fable and opus by default on
Claude Code).

## Precondition

An active intent MUST exist in INDEX.md. If none exists, refuse: "No active intent found. Create one first with /plastic-intent-creating."

If multiple active intents exist, ask the user which one to deliver (this is the only question auto asks).

**Picking work when no intent is specified.** If the user says "auto" without naming an
intent and none is active, consult the roadmap first (the primary planning surface), then
fall back to the dashboard queue. Read the tier's mid-flight roadmap:

```bash
ruby ~/.plastic/scripts/roadmap-next --roadmaps-dir <tier>/roadmaps
```

Branch on `state`:
- `dispatchable`: work its `dispatchable_queue` in `rank` order (the head is the next batch
  entry). These are the current batch's `queued` intents, parallel-safe within the wave.
- `in_flight`: the frontier batch is still delivering. Report it and wait. Do NOT dispatch a
  later batch and do NOT fall through to the dashboard, the roadmap is live.
- `none` or `exhausted`: no roadmap, or nothing left to dispatch. Fall back to the dashboard
  queue below. (The global store has no roadmap, so it always reports `none` and falls back.)

Dashboard fallback:

```bash
ruby ~/.plastic/scripts/dashboard.rb all --json
```

Work `dispatchable_queue` in `rank` order (these are `defer`/`research` dispositions -
safe to deliver autonomously). Leave `human_only` and `next_big_thing` for the user - those
are `drive`/`triage` items the human should lead. See the `plastic-dashboard` skill.

QMD-first (when available): when the user describes the work to deliver rather than naming an
intent, before scanning the store with grep/Read run
`ruby ~/.plastic/scripts/qmd-sync search "<terms>"` to surface candidate, prior, or duplicate
intents, then open the authoritative intent file for the hit you take over. The command is a no-op
when QMD is absent, so fall back to the existing INDEX.md / file scan. (This is discovery; the
reindex step under Completion is separate.)

## Tiers (proportional auto sizing)

Auto mode sizes every intent S/M/L at Why, deterministically, then matches agent topology
and artifact depth to that size. Extended walkthrough: `references/tiers.md`.

1. **Sizing rule.** S = single mechanism or file cluster (hours). M = one subsystem (a
   day). L = cross-cutting or novel design.
2. **Two levers.** Speed comes only from artifact content DEPTH and agent TOPOLOGY. The
   same-structure invariant (same file set, stage order, gates, savepoint ledger) holds at
   every tier and in both modes. A three-line spec.md is still a spec.md, in the same
   place, under the same gate.
3. **Per-tier topology.** S/M: one thinker agent, one boot, two stations, sonnet
   executor; the thinker writes at least one real action file (one consolidated
   `actions/ACTION_1.md`), never an empty `actions/`. S may also skip the QMD discovery
   deposit when chain and sources are both empty. L: today's full team (`## Team Spin-Up`
   below), one `actions/ACTION_N.md` per task.
4. **Never-cut list**, any tier or mode: the independent reviewer (separate agent, fresh
   context, never the maker), `outcome.md` as truth of delivery, the delivery lock,
   worktree isolation, intent creation via skill, INDEX as status truth, the QMD reindex
   at End. Lightness is about ceremony, never about these guarantees.
5. **Tier record.** `Tier: S|M|L` at the top of spec.md. Convention-only: read by the
   orchestrator, never validated by any gate or by doctor.

## Arm the Lifecycle Gate (do this FIRST)

Immediately after selecting the intent - before any other work - arm auto mode. This
writes the session bridge that makes the code-edit gate live, so project code cannot be
edited before the plan exists (the gate applies to YOU, the orchestrator):

```bash
ruby -r ~/.plastic/scripts/lib/bridge -e \
  'Bridge.arm_auto(ENV["CLAUDE_CODE_SESSION_ID"], intent_id: "<ID>", intent_dir: "<STORE>/<dir>", store: "<STORE>", name: "<name>")'
```

Replace `<ID>`, `<STORE>` (e.g. `~/.plastic/projects/<slug>/store` or `~/.plastic/store`),
`<dir>` (the `ID--slug` directory), and `<name>`. The first argument is the session id you
want the bridge keyed by: pass the hook stdin `session_id` when you have it, otherwise
`ENV["CLAUDE_CODE_SESSION_ID"]`, otherwise `nil`. Arming always succeeds and acquires the
durable `delivery.lock` in the intent dir. For the `resolve_session` fallback chain
(why arming never needs a non-empty session env var, and what the lock ownership model
implies for later tool calls) read `references/end-tail.md`.

**Hard rule for the rest of this run:** do NOT edit project code (anything outside the
intent directory / `~/.plastic/`) until `plan.md` AND `checklist.md` exist for the intent.
Honor the cycle: What → Why (spec.md) → How (plan.md + actions/ + checklist.md) → Exec.

## Flags

- `--skip-permissions` - bypass hard stops on destructive actions on existing projects. Full trust mode. Default: off.

## Team Spin-Up

This is the L-tier shape (see `## Tiers` above); S/M collapse it to one thinker agent.

Auto mode spins up exactly ONE enforcer-led team per intent. The plastic-enforcer IS this orchestrator (you), not a separately dispatched agent, which avoids the who-gates-the-gater regress.

Roster (one role per cycle stage):

- **plastic-brainstorming** (Why exploration): enriches `## Context` + `### Decisions`
- **plastic-spec-specialist** (`spec.md`)
- **plastic-planner** (`plan.md` + `actions/` + `checklist.md`)
- **plastic-executor** (code + checklist + `## Insights`)
- **plastic-enforcer** (orchestrates + gates; that is YOU)

Dispatch rule: sequential, one specialist per stage on one branch (the deliverables share files). Gate each deliverable against the stage's exit criteria before handing off. The How and Exec phases below default to Plastic's native dispatch (`plastic-intent-executing`) and delegate to the superpowers skills only when they are available or the user asks; do not restate the phase mechanics here.

Spawn preamble (live-state injection): before dispatching any specialist, run `scripts/spawn-preamble <intent_dir> --role <role>` and PREPEND its output to that specialist's prompt. The preamble is a deterministic, filesystem-only snapshot of the active intent (id, intent line, current stage, and the provisioned code worktree path when one exists on disk) plus the honoring instruction, so every spawned agent boots with accurate live state instead of guessing. This is the authoritative L2 mechanism for harnesses whose sub-agents do not inherit a top-level session event (see `docs/reference/harness-adapters.md`).

Dispatch-time model contract (belt-and-braces): alongside the preamble, resolve each specialist's model through the config chain (`read-config agents.models.<basename> --project <repo>`: project override, then global, then the shipped tier default) and pass it explicitly at dispatch. Never rely on the dispatched role's frontmatter alone; a resolved subagent model is never Fable,
unless an explicit `agents.models.<name>` config override names Fable for that role, in which
case the override is honored as written. The two advisors, `plastic-advisor` and
`plastic-faux-advisor`, are not lifecycle stage roles: the never-Fable rule governs stage
agents only. Neither is ever dispatched by the auto pipeline; they are consultation roles
summoned deliberately by the user or the main session, and their models are user configuration
(fable and opus by default on Claude Code).

Completion report (require-then-synthesize): every dispatched specialist MUST end with a structured completion report as its final message. The preamble's `REPORT_CONTRACT` injects this and the role prompts carry the per-role format (see `references/agent-report-contract.md`). Because child-agent honor is best-effort across harnesses, this is decision-shaping, not a hard block. When a specialist returns no usable report (it went idle, emitted only a bare ping, or its message was lost to a mid-run interjection), run `scripts/agent-report <intent_dir> --role <role>` to synthesize a deterministic filesystem-derived report so the handoff account always exists. Use the agent-authored report when present, the synthesized one otherwise.

Final-gate review: dispatch an independent reviewer subagent at the final gate only, not as a standing role.

### Delegation (subagents writing under the owner's lock)

The enforcer's session owns the delivery lock. Per-stage specialists run in
their own sessions and would be denied by the lock gate, so register each one
as a delegate before (or when) it needs to write into the intent dir:

1. Instruct each spawned specialist to report its session id
   (`CLAUDE_CODE_SESSION_ID`) in its first message.
2. As the lock owner, run:
   `ruby ~/.plastic/scripts/plastic-lock delegate --delegate <specialist-session-id>`
3. If a specialist hits a lock-gate deny, the deny message names this exact
   command; run it and have the specialist retry.

Only the owner can delegate. Delegates cannot re-delegate or release.

Headless manual gate: when running headless or in the background, still enforce gates manually rather than relying on hooks alone. The PostToolUse gate hook reads `session_id` from hook stdin, and the savepoint ledger write is decoupled from the bridge (derived from the file path, so it fires even with no session id) - these do NOT no-op. What can degrade is the bridge-keyed stage enforcement: if no session id reaches the bridge and no matching bridge is discovered, the stage-gate enforcement step exits without acting, so verify state yourself. The bridge still resolves arming via `CLAUDE_CODE_SESSION_ID` or the derived-key fallback (see the arm-gate note above).

Solo fallback: if the harness has no subagent dispatch, fall back to a single agent walking the full What, Why, How, Exec cycle yourself. This preserves current behavior.

## Stage-Aware Entry

Read the active intent's `savepoint.md` FIRST (intent 81): the last line classifies the stage,
and you then verify only that line's artifact before entering. Fall back to the filesystem probe
below only when the ledger is missing (then rebuild it with `Bridge.rebuild_savepoint`).

| Ledger last line | Enter |
|---|---|
| `What  {id}--{slug}.md` (born) or no spec | Start / complete Why (write spec.md) |
| `Why  spec.md created` | Enter How |
| `How  plan.md created` / `How  checklist.md created` / `Exec  started` | Enter Exec (verify plan + checklist) |
| `Exec  outcome.md created` | Exec done; complete the intent |
| `Done  delivered|abandoned` | Terminal; do not resume |

Filesystem fallback (ledger missing only):

| Check (in order) | Stage |
|---|---|
| `checklist.md` exists with some items checked | Resume Exec from last unchecked item |
| `plan.md` + `checklist.md` exist (no items checked) | Enter Exec |
| `spec.md` exists, no `plan.md` | Enter How |
| `## Context` has content in intent file, no `spec.md` | Complete Why (fill gaps, write spec.md) |
| Only `## Intent` exists | Start Why from scratch |

Announce which stage you're entering and why.

Notify user (What briefing): brief per `references/human-report-contract.md`
(State: the work picked up and why it matters now; Risk: scope uncertainty; Call: confirm
this is worth doing, or proceed).

## Why Completion (Autonomous)

When entering at Why stage:

1. Read existing `## Context` and `### Decisions` from the intent file
2. Assess gaps - what decisions are missing? What context is incomplete?
3. Self-directed research - read code, search docs, explore related intents (via wikilinks in `## Links`), web search if needed. NO questions to human.
4. Adaptive budget - assess complexity and set your own research budget:
   - Simple (config change, small feature): 2-3 research steps
   - Medium (new feature, integration): 5-8 research steps
   - Complex (new project, architecture): 10-15 research steps
5. Make decisions - pick best option, document in `## Context > ### Decisions` with rationale
6. Log all autonomous decisions in `## Insights` with `(autonomous)` marker: "Decision: chose X because Y (autonomous)"
7. Write `spec.md` - consolidated specification
8. Notify user (Why briefing): brief per `references/human-report-contract.md`
   (State: the approach chosen, one line; Risk: the main trade-off; Call: the one decision
   needed, approve or pick an option).

Then proceed to How.

## How Phase

Every tier runs all four steps below (see `## Tiers` above). The `actions/` directory is
scaffolded (with a `.gitkeep`) at intent birth; the planner then writes at least one REAL
`ACTION_N.md` into it at every tier. The tier only changes step 3's granularity: S/M write
one consolidated `actions/ACTION_1.md`, L writes one `actions/ACTION_N.md` per task. A
`.gitkeep`-only or empty `actions/` fails the How gate.

1. If `superpowers:writing-plans` is available as a skill, delegate plan creation to it. Tell it the plan saves to the active intent's directory (not `docs/superpowers/plans/`).
2. Otherwise, write `plan.md` directly - implementation plan with numbered tasks
3. Write at least one real `ACTION_N.md` into the existing `actions/` directory, self-contained (S/M: one consolidated `ACTION_1.md`; L: one per task)
4. Write `checklist.md` - execution registry with checkboxes covering all actions
5. Notify user (How briefing): brief per `references/human-report-contract.md`
   (State: the plan shape, task count and what it builds; Risk: the riskiest task or
   dependency; Call: approve the plan to build).

Then proceed to Exec.

## Project Creation Gate

If the plan calls for creating a new project (the intent is an implementation intent that needs a new codebase):

1. Determine project path from `~/.plastic/config.yml` `project_roots` or from intent context
2. **Confirm path with user** - this is the ONE human interaction during auto delivery:
   > "Creating project `<slug>` at `<path>`. Confirm path, or provide alternative."
3. Invoke `plastic-project-creating` skill
4. The global intent is now Completed (creating-project handles this)
5. The tactical mirror in the project store becomes the active intent
6. Continue execution from the project directory using the tactical intent

## Exec Phase

1. If `superpowers:subagent-driven-development` or `superpowers:executing-plans` is available, delegate execution to it
2. Otherwise invoke `plastic-intent-executing`
3. Execute actions from checklist sequentially
4. Check off items in `checklist.md` as completed
5. Append observations to `## Insights` with `(autonomous)` marker
6. Sub-agents can be spawned for parallel actions (one agent per action)
7. Notify user (Exec briefing): brief per `references/human-report-contract.md`
   (State: what got built and the test result; Risk: residual failures or deviations;
   Call: go to review, or done).

## Permission Model - Safe-by-Default

The agent MUST prefer non-destructive routes:

| Instead of... | Do this... |
|---|---|
| Drop table | Rename to `_deprecated_<table>`, flag for cleanup |
| Delete files | Move to `.archive/` or backup branch |
| Alter column | Additive migration - new column + backfill |
| Remove feature | Feature flag off, code stays until human confirms |
| Database migration | Backup before migration, keep rollback path |

### Hard Stop (without `--skip-permissions`)

When a genuinely destructive action on an existing project has NO safe alternative:
1. Log the proposed action in `## Insights`
2. Notify user: "Blocked on destructive action: [description]. Approve to continue, or provide alternative direction."
3. **STOP and wait for human response.** Do not proceed.

With `--skip-permissions`, the agent logs the action in Insights but proceeds without stopping.

### Greenfield Exception

During initial project creation, all decisions are non-destructive by definition (there's nothing to destroy). The agent has full autonomy for greenfield choices - DB engine, framework, gems, architecture.

## Completion

1. Verify all checklist items are checked
2. Write `outcome.md` with detailed results, from `${CLAUDE_PLUGIN_ROOT}/templates/outcome.md`.
   Set the frontmatter `disposition: delivered` (this is the delivered terminal). `outcome.md`
   is mandatory at every terminal and self-declares its disposition (see the canonical done-marker
   and End tail in PLASTIC.md `## Delivery Isolation and the Single-Owner Lock`).
3. Write `## Outcome` summary in the intent file (1-2 sentences)
4. **Release (if configured)**
   1. Detect project - match CWD against paths in `~/.plastic/projects.yml` to find the project slug. If no match, skip to step 5 (default commit-only behavior).
   2. Read `~/.plastic/projects/{slug}/project.yml`. If the file doesn't exist or has no `release` key, skip to step 5.
   3. Based on `release.on_complete`:
      - `commit` - git add + commit (same as default, proceed to step 5)
      - `commit_and_push` - git add + commit + push
      - `manual` - skip auto-commit, notify user: "Release configured as manual - commit when ready."
   4. If `release.verify` is set, run the verify command (e.g. `bundle exec rake test`):
      - **Exit 0 (green):** proceed to sub-step 5
      - **Non-zero (red):** check `release.on_red`:
        - `fix_and_retry` - attempt to fix the failure, re-run verify (max 2 retries)
        - `stop` - write `savepoint.md` with current state, notify user: "Verify failed - savepoint written.", **STOP**
        - `manual` - notify user: "Verify failed: [summary]. Resolve manually."
   5. If `release.on_green` has items, invoke `plastic-releasing` to handle them (tag, changelog, publish, etc.). Do NOT duplicate release logic - delegate entirely.
5. Review `## Insights` for observations that should spawn future intents. If any:
   - Create them (using `plastic-intent-creating` conventions)
   - Update `chain` in the current intent's frontmatter
6. Run the mechanical close through `plastic-intent-ending`: it owns steps 1-6 of the Done
   procedure (outcome/INDEX/savepoint/commit, disarm, and the QMD reindex last) as ONE
   delegation, not five separate one-liners restated here. Run its backing script for the
   outcome/INDEX/savepoint/commit core, passing `--index-note` with a rich Completed/
   Abandoned entry description (mode/tier, what shipped or why abandoned, suite result):
   ```bash
   ruby ~/.plastic/scripts/end-intent --store <store_path> --id <ID> --disposition delivered \
     --index-note "<mode, tier>; <what shipped>; <suite result>"
   ```
   (Use `--disposition abandoned` when the intent is being moved to `## Abandoned`.) Then
   follow `plastic-intent-ending`'s Step 5 (disarm: `Bridge.disarm_auto` on this auto/curator
   path, the plain-remove branch) and Step 6 (QMD reindex, async, last) exactly as that skill
   states them. Never leave an orphaned worktree; run `git worktree prune` on a stale
   reference. If any of this ever needs to change, change `plastic-intent-ending`, not this
   skill.
7. Notify user (Done briefing): brief per `references/human-report-contract.md`
    (State: the delivered impact; Risk: residual risk; Call: the decision left to you, merge,
    release, or accept). See `outcome.md` for details.

## Error Handling

If the agent gets stuck (can't resolve a gap, dependency is missing, tests fail persistently):
1. Log the blocker in `## Insights`
2. Write `savepoint.md` with current state
3. Notify user: "Blocked on intent [ID] - [name]: [description]. Savepoint written."
4. **STOP.** Do not attempt workarounds that could leave the project in a broken state.

## References

- Read `references/agent-architecture.md` for the full team model (the 5-role enforcer-led team, per-stage handoffs, gate ownership, headless note, solo fallback) and the orchestrator hierarchy (Main Orchestrator, Project Orchestrators, coordination loop) when spinning up the team or understanding autonomous delivery scope
- Read `references/tiers.md` for the extended per-tier walkthrough (S/M/L worked examples, the collapsed one-thinker flow, the QMD-skip case for S) and rationale
- Read `references/human-report-contract.md` for the human-facing per-stage briefing (the
  State/Risk/Call skeleton used at each "Notify user" step above, and how it differs from the
  internal `agent-report-contract.md`)
- Read `references/end-tail.md` for the `resolve_session` fallback chain and the disarm
  ordering / worktree cleanup / QMD reindex rationale referenced above
