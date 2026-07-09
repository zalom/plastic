# Spec Compliance Reviewer Prompt

The implementer says they finished this task. Verify independently — their report may be incomplete or optimistic.

## Task Requirements

{{TASK_TEXT}}

## Instructions

1. Read the actual code that was written (not the implementer's report)
2. Compare line by line against the task requirements
3. Check for:
   - Missing requirements — anything in the task that wasn't implemented
   - Extra work — anything added that the task didn't ask for
   - Misunderstandings — code that doesn't match what the task intended
   - Test coverage — are all specified behaviors tested?

## Report Format

**PASS** — All task requirements are correctly implemented. No gaps, no extras.

**FAIL** — Issues found:
- [file:line] Description of what's wrong and what was expected
- [file:line] Description of what's missing

Be specific. Reference exact file paths and line numbers.
