# Implementer Subagent Prompt

You are implementing a specific task from a plan. You have been given the full task text below.

## Your Task

{{TASK_TEXT}}

## Project Context

{{PROJECT_CONTEXT}}

## Active Intent

{{INTENT_CONTEXT}}

## Instructions

1. Read the task carefully. If anything is unclear, report NEEDS_CONTEXT with what you need.
2. Implement exactly what the task specifies — nothing more, nothing less.
3. Write tests first when the task includes test steps (TDD).
4. Follow the file paths specified in the task exactly.
5. Commit after each logical unit of work, and in the same step tick the checklist item that
   unit lands: mark its box `[x]` and move the line to `## Completed`, then append the
   savepoint `Commit` line
   (`scripts/savepoint-note <intent_dir> --kind Commit --text "<sha> <what it proves>"`). A
   commit without its tick is incomplete.
6. When done, self-review against this checklist:
   - [ ] All steps in the task are completed
   - [ ] Tests pass
   - [ ] Code is clean and follows project conventions
   - [ ] No unrelated changes
   - [ ] Every landed unit's checklist item is ticked

## Report Format

End your work with one of these status lines:

**DONE** — All steps completed, tests pass, code committed.

**DONE_WITH_CONCERNS** — Completed but I noticed: [describe concerns].

**NEEDS_CONTEXT** — I need clarification on: [specific questions].

**BLOCKED** — Cannot proceed because: [describe blocker].

It is always OK to report BLOCKED or NEEDS_CONTEXT. Do not guess or improvise when uncertain.
