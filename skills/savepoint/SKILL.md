---
name: plastic:savepoint
description: Use when context is being compacted (PreCompact hook), user says "save" or "savepoint", or before ending a session. Saves the active intent's state so work can resume after /clear.
---

# Savepoint

## When to Use
- PreCompact hook fires (automatic)
- User says "save", "savepoint", or "save progress"
- Before ending a long session
- Before switching to a different intent

## Workflow

### 1. Find Active Intent(s)
Read `.plastic/INDEX.md` and extract all intents listed under `## Active`.

### 2. For Each Active Intent
Read the intent directory at `.plastic/store/ID--slug/`:

**a. Update checklist.md** (if exists):
- Check off completed items
- Add any new items discovered during the session

**b. Create/update savepoint.md:**
```markdown
# Savepoint

## Last Updated
{{DATE}} — Session #{{N}}

## In Progress
- (what was being worked on when savepoint triggered)
- Next: (immediate next step)

## Blockers
(any blockers or open questions)

## Key Discoveries This Session
- (important things learned)
```

**c. Update `{ID}--{slug}.md`:**
- Add observations to `## Insights` section

### 3. Update INDEX.md
Verify the `## Active` section is accurate.

### 4. Commit
```bash
git add .plastic/
git commit -m "chore: savepoint — [active intent name]"
```

### 5. Notify User
Tell the user: "Context is getting large. I've saved progress to intent [ID] — [name]. Please run `/clear` and say `continue` to resume."
