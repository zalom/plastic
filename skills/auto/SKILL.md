---
name: plastic:auto
description: >-
  Autonomous intent delivery — agent takes over How and Exec. Use when user says
  "auto", "take it from here", "deliver this", or when brainstorming-grill-me concludes
  and user confirms autonomous execution. Requires an active intent in INDEX.md.
---

# Auto — Autonomous Intent Delivery

Announce: "Taking over intent [ID] — [name] for autonomous delivery."

## Precondition

An active intent MUST exist in INDEX.md. If none exists, refuse: "No active intent found. Create one first with /plastic:creating-intent."

If multiple active intents exist, ask the user which one to deliver (this is the only question auto asks).

## Flags

- `--skip-permissions` — bypass hard stops on destructive actions on existing projects. Full trust mode. Default: off.

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
3. Invoke `plastic:creating-project` skill
4. The global intent is now Completed (creating-project handles this)
5. The tactical mirror in the project store becomes the active intent
6. Continue execution from the project directory using the tactical intent

## Exec Phase

1. If `superpowers:subagent-driven-development` or `superpowers:executing-plans` is available, delegate execution to it
2. Otherwise invoke `plastic:executing-plan`
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
4. Review `## Insights` for observations that should spawn future intents. If any:
   - Create them (using `plastic:creating-intent` conventions)
   - Update `chain` in the current intent's frontmatter
5. Move intent from `## Active` to `## Completed` in INDEX.md (with today's date)
6. Auto-commit: `cd <store-root> && git add . && git commit -m "feat: deliver intent <ID> — <name>"`
7. Notify user: "Intent [ID] — [name] delivered. [1-2 sentence summary]. See outcome.md for details."

## Error Handling

If the agent gets stuck (can't resolve a gap, dependency is missing, tests fail persistently):
1. Log the blocker in `## Insights`
2. Write `savepoint.md` with current state
3. Notify user: "Blocked on intent [ID] — [name]: [description]. Savepoint written."
4. **STOP.** Do not attempt workarounds that could leave the project in a broken state.
