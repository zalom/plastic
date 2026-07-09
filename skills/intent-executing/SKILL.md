---
name: plastic-intent-executing
description: Use when you have a written implementation plan to execute. Default mode is subagent-driven (dispatches fresh subagent per task with two-stage review). Fallback mode is inline execution for environments without subagent support. If superpowers:subagent-driven-development or superpowers:executing-plans are available, delegates to them.
user-invocable: true
---

# Executing a Plan

## Overview

Load plan from the active intent's `plan.md`, execute all tasks, review between tasks, report when complete.

**Announce at start:** "I'm using the executing-plan skill to implement this plan."

## Mode Selection

### Check for superpowers first
If `superpowers:subagent-driven-development` is available as a skill, delegate to it. If only `superpowers:executing-plans` is available, delegate to that. If neither is available, use Plastic's own execution engine below.

**CRITICAL — when delegating to superpowers:**
- Tell the skill that the plan is at `~/.plastic/store/ID--slug/plan.md` (not `docs/superpowers/plans/`)
- Tell the skill that specs live at `~/.plastic/store/ID--slug/spec.md` (not `docs/superpowers/specs/`)
- All meta-artifacts must stay inside `~/.plastic/store/ID--slug/`
- Code files go in the project tree as normal
- Superpowers skills respect "user preferences for plan/spec location" — Plastic IS that preference

### Subagent-Driven (Default)
Dispatches a fresh subagent per task. Controller never implements — only dispatches, reviews, and tracks progress. Two-stage review after each task: spec compliance first, then code quality.

### Inline (Fallback)
Executes tasks sequentially in the current session. Use when subagents aren't available or user explicitly requests inline mode.

To select: user says "inline", "execute inline", or "no subagents".

## Subagent-Driven Workflow

### Step 1: Load Plan
1. Read the active intent's `plan.md`
2. Extract ALL tasks with their full text — store in memory. Never make subagents read the plan file.
3. Create a task list to track progress

### Step 2: Execute Each Task

For each task sequentially (never parallel — conflict risk):

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

**e. Mark task complete**, move to next

### Step 3: Final Review
After all tasks complete, dispatch a final reviewer for the entire implementation.

### Step 4: Update Intent and Complete
Capture observations in `## Insights`. When ALL checklist items are checked:

1. Write `outcome.md` with detailed results in the intent directory, using the `${CLAUDE_PLUGIN_ROOT}/templates/outcome.md` form. Set the frontmatter `disposition: delivered` (the delivered terminal). `outcome.md` is mandatory at every terminal and self-declares its disposition (canonical done-marker in PLASTIC.md).
2. Write `## Outcome` summary in the intent file (1-2 sentences)
3. Move intent from `## Active` to `## Completed` in INDEX.md (with today's date)
4. Update cluster entries to show `_(completed)_`
5. Auto-commit: `cd <store-root> && git add . && git commit -m "feat: complete intent <ID> — <name>"`
6. QMD reindex LAST (canonical End tail). As the final End-tail step, after the terminal move and any disarm, ALWAYS refresh the QMD search index for this store (no-op when QMD is absent), running in the background so it never blocks the turn: `ruby ~/.plastic/scripts/qmd-sync reindex --store <store-root> --async`. Completion is the lifecycle event that keeps the search index fresh, and the reindex runs last so the index never references a bridge or lock that is about to disappear (see PLASTIC.md `## Delivery Isolation and the Single-Owner Lock`).

**This is NOT optional.** An intent with all checklist items done but no Outcome is a broken state. Complete the intent immediately — do not leave it for later.

## Inline Workflow

### Step 1: Load and Review Plan
1. Read plan file from active intent
2. Review critically — raise concerns before starting
3. Create task list to track progress

### Step 2: Execute Tasks
For each task:
1. Mark as in_progress
2. Follow each step exactly
3. Run verifications as specified
4. Mark as completed

### Step 3: Update Intent and Complete
Capture observations in `## Insights`. When ALL checklist items are checked:

1. Write `outcome.md` with detailed results in the intent directory, using the `${CLAUDE_PLUGIN_ROOT}/templates/outcome.md` form. Set the frontmatter `disposition: delivered` (the delivered terminal). `outcome.md` is mandatory at every terminal and self-declares its disposition (canonical done-marker in PLASTIC.md).
2. Write `## Outcome` summary in the intent file (1-2 sentences)
3. Move intent from `## Active` to `## Completed` in INDEX.md (with today's date)
4. Update cluster entries to show `_(completed)_`
5. Auto-commit: `cd <store-root> && git add . && git commit -m "feat: complete intent <ID> — <name>"`
6. QMD reindex LAST (canonical End tail). As the final End-tail step, after the terminal move and any disarm, ALWAYS refresh the QMD search index for this store (no-op when QMD is absent), running in the background so it never blocks the turn: `ruby ~/.plastic/scripts/qmd-sync reindex --store <store-root> --async`. Completion is the lifecycle event that keeps the search index fresh, and the reindex runs last so the index never references a bridge or lock that is about to disappear (see PLASTIC.md `## Delivery Isolation and the Single-Owner Lock`).

**This is NOT optional.** Complete the intent immediately when work is done.

## Model Selection for Subagents

Match model to task complexity:
- **Mechanical tasks** (config files, boilerplate): cheapest available
- **Standard implementation**: default model
- **Architecture, integration, review**: most capable model

## Prompt Templates

Subagent prompts are in this skill's directory:
- `implementer-prompt.md` — template for implementer subagents
- `spec-reviewer-prompt.md` — template for spec compliance reviewers
- `code-quality-reviewer-prompt.md` — template for code quality reviewers

Read the appropriate template when dispatching each subagent type.
