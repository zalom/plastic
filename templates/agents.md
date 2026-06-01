# Plastic — Project Agent Instructions

> Full conventions: see `~/.plastic/AGENTS.md` (the global agent contract).
> This file covers project-scoped rules only.

## Your Role

You are working on this project as part of a strategic intent. Your governing intent is tracked in the global Plastic store at `~/.plastic/store/`.

## How to Work

1. **Check active tactical intents** in `.plastic/store/` — these are your current tasks
2. **Create new tactical intents** when you discover sub-work needed
3. **Use [[NNN-HASH]] wikilinks** to link intents to each other
4. **Use [[global:NNN-HASH]]** to link back to the governing strategic intent
5. **Auto-commit** all intent changes in this project's git repo

## Intent Lifecycle — What→Why→How→Next

State is derived from filesystem conventions, not frontmatter fields:

| Convention | Signal |
|---|---|
| `## Context` has content | Intent is permanent (not fleeting) |
| `actions/` directory exists | Intent is actionable |
| `## Outcome` has content | Intent is done |

Sections map to the lifecycle:
- **## Intent** — What (the desire)
- **## Context** — Why (background + ### Decisions)
- **## Outcome** — How (the result, deliverables)
- **## Insights** — Next (observations, raw material for future intents)

Active/Future/Completed placement is managed in INDEX.md, not in frontmatter.

## Creating Tactical Intents

1. Scan `.plastic/store/` for the next sequential ID
2. Generate hash: `~/.plastic/scripts/hash-intent "intent name"`
3. Create `.plastic/store/NNN--slug-XXXXXX/intent.md`
4. Set frontmatter: `id`, `intent`, `sources` (array — link to governing intent), `chain` (starts empty), `created`, `author`, `tags`
5. Add `[[global:NNN-HASH]]` backlink in `## Links`

## When You're Done

When this project satisfies the governing intent's goal, report back. The orchestrator will complete the strategic intent.
