# Context Management (Start-Save-Continue)

## Save Point

Triggered by PreCompact hook or manually:

1. Find active intent(s) from `~/.plastic/INDEX.md`
2. Update active intent's `checklist.md` (check off completed items)
3. Update active intent's `savepoint.md` (in-progress, next steps, blockers, discoveries)
4. Add observations to `## Insights`
5. Update INDEX.md
6. Commit: `cd ~/.plastic && git add . && git commit -m "chore: savepoint — [intent name]"`
7. Notify user to `/clear`

## Continue

Triggered by UserPromptSubmit hook when user says "continue". Priority order:

### 1. Active intents first (resume work)

1. Read INDEX.md → find active intent(s)
2. Read active intent's `intent.md` → what and why
3. Read active intent's `savepoint.md` → where we left off
4. Read active intent's `checklist.md` → what's next
5. Announce: intent name, current state, next step, blockers
6. Resume

### 2. No active intents → offer future intents

1. List all future intents from INDEX.md
2. Present them as options
3. When user picks one, move to Active in INDEX.md

### 3. Stale future intents (untouched 3+ days) → triage

- **activate** — start working on it now
- **abandon** — mark as abandoned
- **defer to agent** — implement, research, or ideate
