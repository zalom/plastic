---
name: plastic-auto
description: >-
  Autonomous intent delivery — agent takes over How and Exec. Use when user says
  "auto", "take it from here", "deliver this", or when brainstorming-grill-me concludes
  and user confirms autonomous execution. Requires an active intent in INDEX.md.
---

# Auto — Autonomous Intent Delivery

Announce: "Taking over intent [ID] — [name] for autonomous delivery."

## Precondition

An active intent MUST exist in INDEX.md. If none exists, refuse: "No active intent found. Create one first with /plastic-creating-intent."

If multiple active intents exist, ask the user which one to deliver (this is the only question auto asks).

**Picking work when no intent is specified.** If the user says "auto" without naming an
intent and none is active, consult the dashboard's machine-readable queue to choose the
next dispatchable intent:

```bash
ruby ~/.plastic/scripts/dashboard.rb all --json
```

Work `dispatchable_queue` in `rank` order (these are `defer`/`research` dispositions —
safe to deliver autonomously). Leave `human_only` and `next_big_thing` for the user — those
are `drive`/`triage` items the human should lead. See the `plastic-dashboard` skill.

QMD-first (when available): when the user describes the work to deliver rather than naming an
intent, before scanning the store with grep/Read run
`ruby ~/.plastic/scripts/qmd-sync search "<terms>"` to surface candidate, prior, or duplicate
intents, then open the authoritative intent file for the hit you take over. The command is a no-op
when QMD is absent, so fall back to the existing INDEX.md / file scan. (This is discovery; the
reindex step under Completion is separate.)

## Arm the Lifecycle Gate (do this FIRST)

Immediately after selecting the intent — before any other work — arm auto mode. This
writes the session bridge that makes the code-edit gate live, so project code cannot be
edited before the plan exists (the gate applies to YOU, the orchestrator):

```bash
ruby -r ~/.plastic/scripts/lib/bridge -e \
  'Bridge.arm_auto(ENV["CLAUDE_SESSION_ID"], intent_id: "<ID>", intent_dir: "<STORE>/<dir>", store: "<STORE>", name: "<name>")'
```

Replace `<ID>`, `<STORE>` (e.g. `~/.plastic/projects/<slug>/store` or `~/.plastic/store`),
`<dir>` (the `ID--slug` directory), and `<name>`. If `CLAUDE_SESSION_ID` is unset, `arm_auto`
falls back to a deterministic derived bridge key (a hash of the store and intent id), so the
gate still engages; arming prints a one-line notice to stderr in that case.

**Hard rule for the rest of this run:** do NOT edit project code (anything outside the
intent directory / `~/.plastic/`) until `plan.md` AND `checklist.md` exist for the intent.
Honor the cycle: What → Why (spec.md) → How (plan.md + actions/ + checklist.md) → Exec.

## Flags

- `--skip-permissions` — bypass hard stops on destructive actions on existing projects. Full trust mode. Default: off.

## Team Spin-Up

Auto mode spins up exactly ONE enforcer-led team per intent. The plastic-enforcer IS this orchestrator (you), not a separately dispatched agent, which avoids the who-gates-the-gater regress.

Roster (one role per cycle stage):

- **plastic-brainstorming** (Why exploration): enriches `## Context` + `### Decisions`
- **plastic-spec-specialist** (`spec.md`)
- **plastic-planner** (`plan.md` + `actions/` + `checklist.md`)
- **plastic-executor** (code + checklist + `## Insights`)
- **plastic-enforcer** (orchestrates + gates; that is YOU)

Dispatch rule: sequential, one specialist per stage on one branch (the deliverables share files). Gate each deliverable against the stage's exit criteria before handing off. The How and Exec phases below default to Plastic's native dispatch (`plastic-executing-plan`) and delegate to the superpowers skills only when they are available or the user asks; do not restate the phase mechanics here.

Spawn preamble (live-state injection): before dispatching any specialist, run `scripts/spawn-preamble <intent_dir> --role <role>` and PREPEND its output to that specialist's prompt. The preamble is a deterministic, filesystem-only snapshot of the active intent (id, intent line, current stage) plus the honoring instruction, so every spawned agent boots with accurate live state instead of guessing. This is the authoritative L2 mechanism for harnesses whose sub-agents do not inherit a top-level session event (see `docs/reference/harness-adapters.md`).

Completion report (require-then-synthesize): every dispatched specialist MUST end with a structured completion report as its final message. The preamble's `REPORT_CONTRACT` injects this and the role prompts carry the per-role format (see `references/agent-report-contract.md`). Because child-agent honor is best-effort across harnesses, this is decision-shaping, not a hard block. When a specialist returns no usable report (it went idle, emitted only a bare ping, or its message was lost to a mid-run interjection), run `scripts/agent-report <intent_dir> --role <role>` to synthesize a deterministic filesystem-derived report so the handoff account always exists. Use the agent-authored report when present, the synthesized one otherwise.

Final-gate review: dispatch an independent reviewer subagent at the final gate only, not as a standing role.

Headless manual gate: when running headless or in the background, enforce gates manually and do not rely on hooks, because `CLAUDE_SESSION_ID` may be unset (this ties to the arm-gate fallback above).

Solo fallback: if the harness has no subagent dispatch, fall back to a single agent walking the full What, Why, How, Exec cycle yourself. This preserves current behavior.

## Stage-Aware Entry

Read the active intent's directory. Determine current lifecycle stage from filesystem state:

| Check (in order) | Stage |
|---|---|
| `checklist.md` exists with some items checked | Resume Exec from last unchecked item |
| `plan.md` + `checklist.md` exist (no items checked) | Enter Exec |
| `spec.md` exists, no `plan.md` | Enter How |
| `## Context` has content in intent file, no `spec.md` | Complete Why (fill gaps, write spec.md) |
| Only `## Intent` exists | Start Why from scratch |

Announce which stage you're entering and why.

## Why Completion (Autonomous)

When entering at Why stage:

1. Read existing `## Context` and `### Decisions` from the intent file
2. Assess gaps — what decisions are missing? What context is incomplete?
3. Self-directed research — read code, search docs, explore related intents (via wikilinks in `## Links`), web search if needed. NO questions to human.
4. Adaptive budget — assess complexity and set your own research budget:
   - Simple (config change, small feature): 2-3 research steps
   - Medium (new feature, integration): 5-8 research steps
   - Complex (new project, architecture): 10-15 research steps
5. Make decisions — pick best option, document in `## Context > ### Decisions` with rationale
6. Log all autonomous decisions in `## Insights` with `(autonomous)` marker: "Decision: chose X because Y (autonomous)"
7. Write `spec.md` — consolidated specification

Then proceed to How.

## How Phase

1. If `superpowers:writing-plans` is available as a skill, delegate plan creation to it. Tell it the plan saves to the active intent's directory (not `docs/superpowers/plans/`).
2. Otherwise, write `plan.md` directly — implementation plan with numbered tasks
3. Create `actions/` directory with `ACTION_N.md` files (one per task, self-contained)
4. Write `checklist.md` — execution registry with checkboxes covering all actions

Then proceed to Exec.

## Project Creation Gate

If the plan calls for creating a new project (the intent is an implementation intent that needs a new codebase):

1. Determine project path from `~/.plastic/config.yml` `project_roots` or from intent context
2. **Confirm path with user** — this is the ONE human interaction during auto delivery:
   > "Creating project `<slug>` at `<path>`. Confirm path, or provide alternative."
3. Invoke `plastic-creating-project` skill
4. The global intent is now Completed (creating-project handles this)
5. The tactical mirror in the project store becomes the active intent
6. Continue execution from the project directory using the tactical intent

## Exec Phase

1. If `superpowers:subagent-driven-development` or `superpowers:executing-plans` is available, delegate execution to it
2. Otherwise invoke `plastic-executing-plan`
3. Execute actions from checklist sequentially
4. Check off items in `checklist.md` as completed
5. Append observations to `## Insights` with `(autonomous)` marker
6. Sub-agents can be spawned for parallel actions (one agent per action)

## Permission Model — Safe-by-Default

The agent MUST prefer non-destructive routes:

| Instead of... | Do this... |
|---|---|
| Drop table | Rename to `_deprecated_<table>`, flag for cleanup |
| Delete files | Move to `.archive/` or backup branch |
| Alter column | Additive migration — new column + backfill |
| Remove feature | Feature flag off, code stays until human confirms |
| Database migration | Backup before migration, keep rollback path |

### Hard Stop (without `--skip-permissions`)

When a genuinely destructive action on an existing project has NO safe alternative:
1. Log the proposed action in `## Insights`
2. Notify user: "Blocked on destructive action: [description]. Approve to continue, or provide alternative direction."
3. **STOP and wait for human response.** Do not proceed.

With `--skip-permissions`, the agent logs the action in Insights but proceeds without stopping.

### Greenfield Exception

During initial project creation, all decisions are non-destructive by definition (there's nothing to destroy). The agent has full autonomy for greenfield choices — DB engine, framework, gems, architecture.

## Completion

1. Verify all checklist items are checked
2. Write `outcome.md` with detailed results
3. Write `## Outcome` summary in the intent file (1-2 sentences)
4. **Release (if configured)**
   1. Detect project — match CWD against paths in `~/.plastic/projects.yml` to find the project slug. If no match, skip to step 5 (default commit-only behavior).
   2. Read `~/.plastic/projects/{slug}/project.yml`. If the file doesn't exist or has no `release` key, skip to step 5.
   3. Based on `release.on_complete`:
      - `commit` — git add + commit (same as default, proceed to step 5)
      - `commit_and_push` — git add + commit + push
      - `manual` — skip auto-commit, notify user: "Release configured as manual — commit when ready."
   4. If `release.verify` is set, run the verify command (e.g. `bundle exec rake test`):
      - **Exit 0 (green):** proceed to sub-step 5
      - **Non-zero (red):** check `release.on_red`:
        - `fix_and_retry` — attempt to fix the failure, re-run verify (max 2 retries)
        - `stop` — write `savepoint.md` with current state, notify user: "Verify failed — savepoint written.", **STOP**
        - `manual` — notify user: "Verify failed: [summary]. Resolve manually."
   5. If `release.on_green` has items, invoke `plastic-releasing` to handle them (tag, changelog, publish, etc.). Do NOT duplicate release logic — delegate entirely.
5. Review `## Insights` for observations that should spawn future intents. If any:
   - Create them (using `plastic-creating-intent` conventions)
   - Update `chain` in the current intent's frontmatter
6. Move intent from `## Active` to `## Completed` in INDEX.md (with today's date)
7. Auto-commit: `cd <store-root> && git add . && git commit -m "feat: deliver intent <ID> — <name>"`
8. On completion, ALWAYS refresh the QMD search index for this store (no-op when QMD is absent).
   It runs in the background so it never blocks the turn:
   ```bash
   ruby ~/.plastic/scripts/qmd-sync reindex --store <store-root> --async
   ```
   Completion is the lifecycle event that keeps the search index fresh. `<store-root>` is the
   store that holds this intent (the global store or the project store).
9. Disarm the lifecycle gate (auto delivery is finished):
   ```bash
   ruby -r ~/.plastic/scripts/lib/bridge -e 'Bridge.disarm_auto(ENV["CLAUDE_SESSION_ID"])'
   ```
   Disarming also purges stale bridge files from the temp directory automatically (it keeps the
   current bridge and any live run), so no manual `/tmp` cleanup is needed.
10. Notify user: "Intent [ID] — [name] delivered. [1-2 sentence summary]. See outcome.md for details."

## Error Handling

If the agent gets stuck (can't resolve a gap, dependency is missing, tests fail persistently):
1. Log the blocker in `## Insights`
2. Write `savepoint.md` with current state
3. Notify user: "Blocked on intent [ID] — [name]: [description]. Savepoint written."
4. **STOP.** Do not attempt workarounds that could leave the project in a broken state.

## References

- Read `references/agent-architecture.md` for the full team model (the 5-role enforcer-led team, per-stage handoffs, gate ownership, headless note, solo fallback) and the orchestrator hierarchy (Main Orchestrator, Project Orchestrators, coordination loop) when spinning up the team or understanding autonomous delivery scope
