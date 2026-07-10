# Plan, Checklist, and Action Format

The exact templates for `plan.md`'s header and task structure, and for the
`checklist.md` and `actions/ACTION_N.md` artifacts. Read this before writing
plan.md so the shape matches on the first pass.

## Table of Contents

- [Plan Document Header](#plan-document-header)
- [Task Structure (worked example)](#task-structure-worked-example)
- [checklist.md format](#checklistmd-format)
- [actions/ACTION_N.md format](#actionsaction_nmd-format)

## Plan Document Header

**Every plan MUST start with this header:**

```markdown
# [Feature Name] Implementation Plan

> **For agentic workers:** Use `plastic-intent-executing` to implement this plan task-by-task.

**Goal:** [One sentence describing what this builds]

**Architecture:** [2-3 sentences about approach]

**Tech Stack:** [Key technologies/libraries]

**Intent:** {id}: {name}

**Tier:** S|M|L, copied from the spec's stamped `Tier:` line. Every tier produces at
least one real `actions/ACTION_N.md`; S and M consolidate the delivery into one action
file, L uses one `actions/ACTION_N.md` per task.

---
```

## Task Structure (worked example)

````markdown
### Task N: [Component Name]

**Files:**
- Create: `exact/path/to/file.rb`
- Modify: `exact/path/to/existing.rb:123-145`
- Test: `test/exact/path/to/test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
def test_specific_behavior
  result = function(input)
  assert_equal expected, result
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/path/test.rb --name test_specific_behavior`
Expected: FAIL with "undefined method"

- [ ] **Step 3: Write minimal implementation**

```ruby
def function(input)
  expected
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `ruby -Itest test/path/test.rb --name test_specific_behavior`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add test/path/test.rb lib/path/file.rb
git commit -m "feat: add specific feature"
```
````

## checklist.md format

Execution registry with one checkbox per task, following this FORM regardless
of tier (S, M, or L):

```markdown
# Checklist: {name}

## In Progress
- [ ] Task 1: {task title}
- [ ] Task 2: {task title}
- [ ] Task 3: {task title}

## Completed
(empty at plan time; move each item here, checked, the moment its task lands)

## Session Log
| Date | Items Completed | Notes |
|------|-----------------|-------|
```

- `## In Progress` holds every unchecked task, in plan order.
- `## Completed` starts empty. As execution lands a task, move its item here
  (checked) instead of leaving a checked box under `## In Progress`.
- `## Session Log` gets one row per work session: the date, which items
  completed, and any deviation or finding worth recording.
- An owner-decision hard-gate item (see the parent SKILL.md's
  `## Owner-decision hard-gate items`) is a normal checklist item prefixed
  `[ORCHESTRATOR]`; it lives under `## In Progress` until the owner rules, then
  moves to `## Completed` like any other item.

## actions/ACTION_N.md format

Every tier writes at least one real action file here (see the parent SKILL.md's
`## Tier shapes`): S and M consolidate the whole delivery into a single
`actions/ACTION_1.md`, L writes one file per task.

Each action is self-contained: a subagent (or a solo executor) can execute it without
reading the plan. It carries the ordered steps to deliver the task plus the exact changes
to make (for code, the anchor or `file:line` and the old/new text).

```markdown
# Action {N}: {task title}

{Full task text copied from plan.md: all steps, all code, all commands. Nothing omitted.}
```

Create the `actions/` directory inside the intent directory: `{intent_dir}/actions/`
