# Plastic project agent instructions

> Full conventions: see `~/.plastic/PLASTIC.md` (the global conventions contract).
> This file covers project-scoped rules only.

## Your role

You are working on this project as part of a strategic intent. Your governing intent is tracked in the global Plastic store at `~/.plastic/store/`.

## Tools

Plastic detects the tools it can use to work faster on this project: QMD (search this
project's intent store instead of grep), and Serena or Enola (symbolic code navigation
instead of grep). None is required. Whichever are present, their readiness is checked every
time this project loads (`doctor --store <slug>`), so working through Plastic on this project
means preferring a detected tool's own search or navigation over a generic file scan.

## How to work

1. **Check active tactical intents** in `.plastic/store/`: these are your current tasks
2. **Create new tactical intents** when you discover sub-work needed
3. **Use [[ID]] wikilinks** to link intents to each other
4. **Use [[global:ID]]** to link back to the governing strategic intent
5. **Auto-commit** all intent changes in this project's git repo

## Intent lifecycle: What, Why, How, Exec

State is derived from filesystem conventions, not frontmatter fields:

| Convention | Signal |
|---|---|
| `## Context` has content | Intent is permanent (developed, actionable) |
| `## Outcome` has content | Intent is done |

Sections map to the lifecycle:
- **## Intent**: What (the desire)
- **## Context**: Why (background + ### Decisions)
- **## Outcome**: Exec (the result; How's deliverables are the `actions/` files and the work graph in `graph.json`)
- **## Insights**: observations across all stages, raw material for future intents

Active/Future/Completed placement is managed in INDEX.md, not in frontmatter.

## Create tactical intents

Create an intent with one call: `plastic intent new "<one-line>" [--parent ID]`.
It allocates the Folgezettel ID, writes the intent rows, creates the intent folder with
`intent.md`, and wires the links. Never hand-author the files or the rows.

## Lifecycle commands

Plastic has its own lifecycle commands. When a Plastic command exists for the current phase, use it instead of any external skill (superpowers, superpowers-ruby, etc.).

| Phase | Command | Produces |
|-------|-------|----------|
| What | `plastic intent new` | Intent file |
| Why | `plastic intent spec` | Rulings as insights, `resources/*.md`, `spec.md` |
| How | `plastic intent spec` | `actions/`, the work graph (`graph.json`) |
| Exec | `plastic node claim`, `plastic node done` | Code + `outcome.md` |
| End | `plastic intent end` | Lifecycle transition |

**Artifact convention:** ALL lifecycle artifacts go to the active intent directory (`store/{id}--{slug}/`). Never write specs to `docs/superpowers/specs/` or plans to `docs/superpowers/plans/`.

## When the project wraps

When this project satisfies the governing intent's goal, report back. The orchestrator will complete the strategic intent.
