---
name: plastic-writing-plans
description: "Write implementation plans from a spec. Produces plan.md, checklist.md, and actions/ in the active intent directory."
---

# Writing Plans

## Overview

Write comprehensive implementation plans assuming the engineer has zero context for our codebase and questionable taste. Document everything they need to know: which files to touch for each task, code, testing, docs they might need to check, how to test it. Give them the whole plan as bite-sized tasks. DRY. YAGNI. TDD. Frequent commits.

Assume they are a skilled developer, but know almost nothing about our toolset or problem domain. Assume they don't know good test design very well.

**Announce at start:** "I'm using the writing-plans skill to plan intent {id} — {name}."

## Active Intent Gate

Before proceeding, resolve the active intent:

1. **Detect store:** Read `~/.plastic/projects.yml`, match CWD against registered project paths. If match → project store at `~/.plastic/projects/{slug}/store/`. If no match → global store at `~/.plastic/store/`.
2. **Find active intent:** Read `INDEX.md` from the detected store. Look under `## Active`. If exactly one → use it. If multiple → ask which. If none → refuse: "No active intent. Create one first with /plastic-creating-intent"
3. **Resolve intent directory:** `{store}/store/{id}--{slug}/`
4. **Read spec:** Load `{intent_dir}/spec.md`. If no spec exists → refuse: "No spec found. Run /plastic-brainstorming first."

All artifacts go to the intent directory. Never write to external paths.

## Scope Check

If the spec covers multiple independent subsystems, it should have been broken into sub-project specs during brainstorming. If it wasn't, suggest breaking this into separate plans — one per subsystem. Each plan should produce working, testable software on its own.

## File Structure

Before defining tasks, map out which files will be created or modified and what each one is responsible for. This is where decomposition decisions get locked in.

- Design units with clear boundaries and well-defined interfaces. Each file should have one clear responsibility.
- You reason best about code you can hold in context at once, and your edits are more reliable when files are focused. Prefer smaller, focused files over large ones that do too much.
- Files that change together should live together. Split by responsibility, not by technical layer.
- In existing codebases, follow established patterns. If the codebase uses large files, don't unilaterally restructure - but if a file you're modifying has grown unwieldy, including a split in the plan is reasonable.

This structure informs the task decomposition. Each task should produce self-contained changes that make sense independently.

## Bite-Sized Task Granularity

**Each step is one action (2-5 minutes):**
- "Write the failing test" - step
- "Run it to make sure it fails" - step
- "Implement the minimal code to make the test pass" - step
- "Run the tests and make sure they pass" - step
- "Commit" - step

## Plan Format

For the exact plan/task/checklist/action format (the Plan Document Header
template, the full Task Structure worked example, and the checklist.md /
actions/ACTION_N.md templates), read `references/plan-format.md` before
writing plan.md. Every plan starts with the header template and decomposes
into tasks matching the Task Structure shape.

## No Placeholders

Every step must contain the actual content an engineer needs. These are **plan failures** — never write them:
- "TBD", "TODO", "implement later", "fill in details"
- "Add appropriate error handling" / "add validation" / "handle edge cases"
- "Write tests for the above" (without actual test code)
- "Similar to Task N" (repeat the code — the engineer may be reading tasks out of order)
- Steps that describe what to do without showing how (code blocks required for code steps)
- References to types, functions, or methods not defined in any task

## Remember
- Exact file paths always
- Complete code in every step — if a step changes code, show the code
- Exact commands with expected output
- DRY, YAGNI, TDD, frequent commits

## Self-Review

After writing the complete plan, look at the spec with fresh eyes and check the plan against it. This is a checklist you run yourself — not a subagent dispatch.

**1. Spec coverage:** Skim each section/requirement in the spec. Can you point to a task that implements it? List any gaps.

**2. Placeholder scan:** Search your plan for red flags — any of the patterns from the "No Placeholders" section above. Fix them.

**3. Type consistency:** Do the types, method signatures, and property names you used in later tasks match what you defined in earlier tasks? A function called `clear_layers` in Task 3 but `clear_full_layers` in Task 7 is a bug.

If you find issues, fix them inline. No need to re-review — just fix and move on. If you find a spec requirement with no task, add the task.

## Plastic Artifacts

After writing `plan.md`, create two additional artifacts in the intent directory:
`checklist.md` (execution registry with one checkbox per task) and
`actions/ACTION_N.md` (one self-contained file per task, in an `actions/`
directory inside the intent directory). For the exact format of both, read
`references/plan-format.md`.

## Git Commit

After writing all artifacts (plan.md, checklist.md, actions/), commit to the store:

```bash
cd {store_root} && git add . && git commit -m "docs: plan for intent {id} — {name}"
```

## Execution Handoff

Plan complete. Invoke `plastic-executing-plan` to begin execution.
