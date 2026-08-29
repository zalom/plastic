---
name: plastic-intent-executing
description: Use when you have a written implementation plan to execute. Default mode is subagent-driven (at L a fresh subagent per task with two-stage review, at S and M one executor dispatch for the whole consolidated action). Fallback mode is inline execution for environments without subagent support. If superpowers:subagent-driven-development or superpowers:executing-plans are available, delegates to them.
user-invocable: true
---

# Executing a Plan

## Overview

Load plan from the active intent's `plan.md`, execute all tasks, review as below, report when complete.

## Step 0: Sync Worktree First

Before Step 1 (Load Plan) in either workflow below, sync the code worktree with
main first, so no edit lands on a path a merged rename or delete already removed:

```
git -C <worktree> fetch origin && git -C <worktree> merge --ff-only origin/main
```

After syncing, verify the plan's target files exist at the paths plan.md names.
If a named file or directory is missing (renamed or removed upstream), stop and
report it rather than editing a stale path.

Read `../plastic-conventions/references/locks-and-worktrees.md` for delivery isolation: the
single-owner lock, claims, worktrees, solo mode, and the station ledger, before touching the
worktree above. This path resolves relative to this skill's own installed directory.

## Mode Selection

### Check for superpowers first
If `superpowers:subagent-driven-development` is available as a skill, delegate to it. If only `superpowers:executing-plans` is available, delegate to that. If neither is available, use Plastic's own execution engine below.

**CRITICAL: when delegating to superpowers:**
- Tell the skill that the plan is at `~/.plastic/store/ID--slug/plan.md` (not `docs/superpowers/plans/`)
- Tell the skill that specs live at `~/.plastic/store/ID--slug/spec.md` (not `docs/superpowers/specs/`)
- All meta-artifacts must stay inside `~/.plastic/store/ID--slug/`
- Code files go in the project tree as normal
- Superpowers skills respect "user preferences for plan/spec location"; Plastic IS that preference

### Subagent-Driven (Default)
Dispatches subagents to do the work. The controller never implements. It dispatches, reviews, and tracks progress. By default one executor dispatch implements the whole consolidated action from `plan.md` plus `checklist.md` in one pass, with no per-task implementer-then-two-reviewers loop. Only when `actions/` holds several independent action files does a fresh subagent take each one, with a two-stage review after each: spec compliance first, then code quality.

The final independent review in Step 3 runs on every delivery. It is a separate agent with fresh context, and it is never the maker.

### Inline (Fallback)
Executes tasks sequentially in the current session. Use when subagents aren't available or user explicitly requests inline mode.

To select: user says "inline", "execute inline", or "no subagents".

## Subagent-Driven Workflow

### Step 1: Load Plan
Run Step 0 (Sync Worktree First) before this step.
1. Read the active intent's `plan.md`
2. Extract ALL tasks with their full text, store in memory. Never make subagents read the plan file.
3. Create a task list to track progress

### Step 2: Execute Each Task

Count the real files under `actions/` first, then follow the matching branch.

#### One consolidated action: one executor dispatch

Dispatch ONE executor subagent and give it the whole delivery: every task's full text from `plan.md` (pasted in, never a file reference), the checklist items it must tick, the project context from CLAUDE.md, and the active intent context from `{ID}--{slug}.md`. In auto mode this is the `plastic-executor` agent; elsewhere use the `implementer-prompt.md` template. The executor implements the consolidated action in order, ticks each item as it lands (see `## Tick-as-you-land`), and drives the test suite green.

Read its response by code:
- DONE or DONE_WITH_CONCERNS → proceed to Step 3. Run no per-task spec review and no per-task quality review here; Step 3's final review covers the work.
- NEEDS_CONTEXT → provide the missing context, re-dispatch the executor.
- BLOCKED → stop, report to the user, wait for resolution.

#### Several independent actions: one subagent per task

For each task sequentially (never parallel: conflict risk):

**a. Dispatch implementer subagent**
Use the Agent tool with the implementer prompt template. Include:
- Full task text (pasted in, not file reference)
- Project context from CLAUDE.md
- Active intent context from `{ID}--{slug}.md`

**b. Handle implementer response**
- DONE → proceed to spec review
- DONE_WITH_CONCERNS → note concerns, proceed to spec review
- NEEDS_CONTEXT → provide missing context, re-dispatch
- BLOCKED → stop, report to user, wait for resolution

**c. Dispatch spec compliance reviewer**
Use the Agent tool with spec-reviewer prompt. The reviewer reads actual code and compares against the task requirements. Pass/fail.
- If fail: implementer fixes, spec reviewer re-reviews (loop until pass)

**d. Dispatch code quality reviewer**
Only after spec compliance passes. Reviews clean code, testing, architecture. Pass/fail.
- If fail: implementer fixes, quality reviewer re-reviews (loop until pass)

**e. Tick as it lands, then move to next**
Follow `## Tick-as-you-land` below: move the task's checklist item to `## Completed` and add a `## Session Log` row in the same edit.

### Step 3: Final Review
After all tasks complete, dispatch a final reviewer for the entire implementation. This runs on every delivery. The reviewer is a separate agent with fresh context and is never the maker. For a consolidated action this is the only review the work gets, so if it returns changes, re-dispatch the executor to fix them, then re-review.

### Step 4: Update Intent and Complete
Capture observations in `## Insights`. When ALL checklist items are checked:

1. Update the intent's cluster entries in `INDEX.md` to show `_(completed)_`. Do this first, so the store auto-commit in the next step picks it up. `plastic-intent-ending` does not cover cluster maintenance (`store-indexing` and `store-curating` own it), so doing it here keeps the step from being lost.
2. Hand the mechanical close to `plastic-intent-ending`. It owns `outcome.md`, the intent file's `## Outcome` stamp, the INDEX terminal move, the savepoint `Done` line, the store auto-commit, disarm, the QMD reindex, and the EM-to-CTO owner report, as ONE delegation. Author the outcome.md content when that skill asks for it; do not restate the mechanical steps here.

**This is NOT optional.** An intent with all checklist items done but no Outcome is a broken state. Complete the intent immediately, do not leave it for later.

## Inline Workflow

### Step 1: Load and Review Plan
Run Step 0 (Sync Worktree First) before this step.
1. Read plan file from active intent
2. Review critically, raise concerns before starting
3. Create task list to track progress

### Step 2: Execute Tasks
For each task:
1. Mark as in_progress
2. Follow each step exactly
3. Run verifications as specified
4. Tick as it lands: follow `## Tick-as-you-land` below

### Step 3: Update Intent and Complete
Capture observations in `## Insights`. When ALL checklist items are checked:

1. Update the intent's cluster entries in `INDEX.md` to show `_(completed)_`. Do this first, so the store auto-commit in the next step picks it up. `plastic-intent-ending` does not cover cluster maintenance (`store-indexing` and `store-curating` own it), so doing it here keeps the step from being lost.
2. Hand the mechanical close to `plastic-intent-ending`. It owns `outcome.md`, the intent file's `## Outcome` stamp, the INDEX terminal move, the savepoint `Done` line, the store auto-commit, disarm, the QMD reindex, and the EM-to-CTO owner report, as ONE delegation. Author the outcome.md content when that skill asks for it; do not restate the mechanical steps here.

**This is NOT optional.** Complete the intent immediately when work is done.

## Tick-as-you-land

As each task lands, in the same edit: move its checklist item from `## In
Progress` to `## Completed` in `checklist.md`, and add one `## Session Log`
row (Date, Items Completed, Notes). Do not batch several tasks' worth of
checklist updates into one later edit; tick the moment the task is verified,
before moving to the next task.

## Verify before every owner gate

Hard rule: before presenting any completed work to the owner, independently
verify it. Grep or run the artifact the work just produced (the test suite,
the changed file, the installed output) rather than restating the intended
change. Never present an unverified claim to the owner. If verification
fails, fix it before the gate, not after.

## Methods report (audits and sweeps)

When the work is an audit or a sweep (checking many files or many instances of
something rather than building one artifact), deposit a methods report to
`{intent_dir}/resources/` before the gate: what was checked, how it was
checked, and what was found. This lets the owner review the method, not just
the conclusion.

## Reroute vs dispatch

A human-facing instruction like "run /plastic-intent-speccing" means the user
types that slash command themselves; it is never handed to a
subagent. Agent-facing dispatch text is a prompt passed to the Agent tool for
a subagent to execute. Keep the two separate: do not address a slash command
to a subagent, and do not paste a dispatch prompt at the user.

## Owner decisions during Exec

When presenting a batch of Exec decisions for the owner to rule, read
`~/.plastic/_decision-tables.md` and follow the numbered-table procedure,
persisting each ruling with `--stage Exec`.

## Gate position

- **Before:** `plan.md` and `checklist.md` exist; the worktree is armed.
- **Produces:** code changes, a ticked checklist, and (for audits or sweeps) a methods report in `resources/`.
- **Next:** `plastic-intent-ending` owns `outcome.md` and the rest of the mechanical close (see intent 161). The Update-Intent-and-Complete step above hands off to it.

Read `../plastic-conventions/references/lifecycle-and-savepoints.md` for the subagent
report-home contract this handoff relies on.

## Model Selection for Subagents

Match model to task complexity:
- **Mechanical tasks** (config files, boilerplate): cheapest available
- **Standard implementation**: default model
- **Architecture, integration, review**: most capable model

## Prompt Templates

Subagent prompts are in this skill's directory:
- `implementer-prompt.md`: template for implementer subagents
- `spec-reviewer-prompt.md`: template for spec compliance reviewers
- `code-quality-reviewer-prompt.md`: template for code quality reviewers

Read the appropriate template when dispatching each subagent type.
