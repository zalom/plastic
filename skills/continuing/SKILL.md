---
name: continuing
description: Use when the user says "continue" after a /clear, or when resuming work in a new session. Reads intent state, offers active intents first, then future intents, and surfaces stale intents for triage.
---

# Continuing

## When to Use
- UserPromptSubmit hook detects "continue" (automatic)
- User says "continue", "resume", or "pick up where we left off"
- Starting a new session with existing active intents

## Workflow

### 1. Read INDEX.md
Read `.plastic/INDEX.md` and extract intents under `## Active` and `## Future`.

### 2. If Active Intents Exist → Resume

For each active intent in `.plastic/store/NNN--slug-XXXXXX/`:

**a. Read intent.md:**
- What we're doing (`## Intent`)
- Why (`## Context`)
- What's been done (`## Build`)
- What's been observed (`## Observe`)

**b. Read savepoint.md** (if exists):
- What was in progress
- What's next
- Any blockers

**c. Read checklist.md** (if exists):
- What's completed
- What's next in the list

**d. Read CLAUDE.md** for methodology and tool priority.

**e. Announce:**
```
Resuming intent NNN — [name]
Status: active
Last session: [date from savepoint]
In progress: [from savepoint]
Next step: [from checklist or savepoint]
Blockers: [from savepoint, or "none"]
```

**f. Resume** — proceed with the next step.

### 3. If No Active Intents → Offer Future Intents

Present future intents as the next work options:

```
No active intents. Here's what's queued:

Future intents:
1. [008 — Extract Plastic plugin] — from: 007+005
2. [009 — Add database layer] — from: 007, after: 008
...

Which intent would you like to activate?
```

Let the user pick. When they choose, update its `status: active` in frontmatter
and move it to the Active section in INDEX.md.

### 4. Surface Stale Future Intents

If any future intent has `updated` date older than 3 days, surface it:

```
Stale future intents (no action taken):

- [NNN — name] (X days old)
  Options:
  a) Activate — start working on it now
  b) Abandon — mark as abandoned, remove from future
  c) Defer to agent — let the agent work on it autonomously:
     - implement: agent builds it (creates plan, writes code)
     - research: agent investigates feasibility, writes findings
     - ideate: agent explores the problem space, proposes approaches
```

For each stale intent the user triages:
- **activate**: update `status: active`, move to Active in INDEX.md
- **abandon**: update `status: abandoned`, move to Completed in INDEX.md with note
- **defer (implement)**: update `status: active`, set `author: claude-code`, create a plan and execute via superpowers:executing-plans
- **defer (research)**: dispatch the `future-intent-researcher` agent on it
- **defer (ideate)**: dispatch the `future-intent-researcher` agent with instructions to explore the problem space broadly, write multiple approaches in a `## Research` section, and leave status as `proposed` for user decision

### 5. Priority Order

Always follow this priority:
1. **Active intents first** — resume the work in progress
2. **Stale future intents** — surface for triage (after active work is announced)
3. **Fresh future intents** — offer as next work if nothing is active
