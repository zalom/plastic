# Plastic — Project Agent Instructions

This project is managed by Plastic, an intent-driven state management system.

## Your Role

You are working on this project as part of a strategic intent. Your governing intent is tracked in the global Plastic store at `~/.plastic/store/`.

## How to Work

1. **Check active tactical intents** in `.plastic_store/` — these are your current tasks
2. **Create new tactical intents** when you discover sub-work needed
3. **Use [[NNN-HASH]] wikilinks** to link intents to each other
4. **Use [[global:NNN-HASH]]** to link back to the governing strategic intent
5. **Auto-commit** all intent changes in this project's git repo

## Intent Lifecycle

```
future → proposed → active → completed | abandoned
```

## Creating Tactical Intents

1. Scan `.plastic_store/` for the next sequential ID
2. Generate hash: `~/.plastic/scripts/hash-intent "intent name"`
3. Create `.plastic_store/NNN--slug-XXXXXX/intent.md`
4. Set `parent` field to the governing intent's NNN-HASH
5. Add `[[global:NNN-HASH]]` backlink in the body

## When You're Done

When this project satisfies the governing intent's goal, report back. The orchestrator will complete the strategic intent.
