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

**Intent:** {id} — {name}

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

Execution registry with one checkbox per task. Format:

```markdown
# Checklist — Intent {id}: {name}

- [ ] Task 1: {task title}
- [ ] Task 2: {task title}
- [ ] Task 3: {task title}
...
```

## actions/ACTION_N.md format

One file per task. Each action is self-contained — a subagent can execute it without reading the plan.

```markdown
# Action {N}: {task title}

{Full task text copied from plan.md — all steps, all code, all commands. Nothing omitted.}
```

Create the `actions/` directory inside the intent directory: `{intent_dir}/actions/`
