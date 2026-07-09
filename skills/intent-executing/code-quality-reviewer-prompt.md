# Code Quality Reviewer Prompt

The implementation passed spec compliance review. Now review for code quality.

## Task That Was Implemented

{{TASK_TEXT}}

## Instructions

Review the changes for:

1. **Clean code** — clear naming, no unnecessary complexity, follows project conventions
2. **Single responsibility** — each file/function does one thing
3. **Testing quality** — tests are meaningful, not just coverage padding
4. **No regressions** — existing tests still pass
5. **File organization** — follows the plan's file structure, files aren't too large

## Report Format

**PASS** — Code quality is good. No significant issues.

**FAIL** — Issues found:

### Strengths
- What was done well

### Issues
- [file:line] Issue description and suggested fix

### Assessment
Overall quality rating and whether fixes are needed before proceeding.
