---
name: plastic:continuing
description: Use when the user says "continue" after a /clear, or when resuming work in a new session. Reads intent state from global store (~/.plastic/) or local store, offers active intents first, then future intents, and surfaces stale intents for triage.
---

# Continuing

## When to Use
- UserPromptSubmit hook detects "continue" (automatic)
- User says "continue", "resume", or "pick up where we left off"
- Starting a new session with existing active intents

## Determine Store

1. Check `~/.plastic/INDEX.md` → global mode
2. Else check `.plastic/INDEX.md` → local/legacy mode
3. If neither exists → announce "No Plastic store found. Run /plastic:install."

## Workflow

### 1. Read INDEX.md
Read the INDEX.md from the active store. Extract intents under `## Active` and `## Future`.

### 2. Detect Current Project (global mode only)
Read `~/.plastic/projects.yml`, match CWD against registered project paths. If in a project:
- Load the governing intent (from `parent` in projects.yml)
- Load tactical intents from `<project>/.plastic/store/`

### 3. If Active Intents Exist → Resume

For each active intent in the store:

**a. Read `{ID}.md`:**
- What we're doing (`## Intent`)
- Why (`## Context`)
- What insights have emerged (`## Insights`)

**b. Read savepoint.md** (if exists):
- What was in progress, what's next, blockers

**c. Read checklist.md** (if exists):
- What's completed, what's next

**d. Announce:**
```
Resuming intent [ID] — [name]
Store: [global | project:<slug> | local]
Status: active
Last session: [date from savepoint]
In progress: [from savepoint]
Next step: [from checklist or savepoint]
Blockers: [from savepoint, or "none"]
```

**e. Resume** — proceed with the next step.

### 3b. Detect Autonomous Resume

When resuming an active intent, check `## Insights` for entries containing `(autonomous)`.

If found — this intent was being delivered autonomously:

**Announce:**
```
Resuming autonomous delivery of intent [ID] — [name]
Store: [global | project:<slug> | local]
Last autonomous action: [last (autonomous) insight entry]
Next step: [from checklist or savepoint]
```

**Then:** Continue autonomous execution by invoking `plastic:auto`. The auto skill will pick up from the current lifecycle stage (it reads filesystem state to determine where to resume).

If NOT found — resume normally as described in step 3.

### 4. If No Active Intents → Offer Future Intents

Present future intents as options. When user picks one, move to Active in INDEX.md. Auto-commit.

### 5. Surface Stale Future Intents

If any future intent has `created` date older than the configured `stale_threshold_days` (default 3):

```
Stale future intents (no action taken):

- [ID — name] (X days old)
  Options:
  a) Activate — start working on it now
  b) Abandon — mark as abandoned
  c) Defer to agent:
     - implement: agent builds it
     - research: agent investigates feasibility
     - ideate: agent explores the problem space
  d) Auto — go fully autonomous (invokes plastic:auto — agent delivers the intent end-to-end)
```

Auto-commit all triage changes.

### 6. Priority Order

1. **Active intents first** — resume work in progress
2. **Project context** — if in a registered project, show governing intent + tactical intents
3. **Stale future intents** — surface for triage
4. **Fresh future intents** — offer as next work
