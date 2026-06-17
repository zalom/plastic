---
name: plastic-creating-project
description: >-
  Create a new project from an implementation intent. Sets up project directory,
  git init, AGENTS.md with founding intent decisions, plastic-install --local,
  tactical mirror, projects.yml registration, and framework scaffolding.
  Use when an implementation intent spawns a project, or manually by user.
---

# Creating a Project

Announce: "Creating project `<slug>` from intent [ID] — [name]."

## Precondition

An active intent must exist with enough context to define a project — at minimum: name/slug, path, and key decisions from `## Context > ### Decisions`.

## Workflow

### 1. Determine Project Identity

- **Slug:** derived from intent name (kebab-case, 2-4 words) or user-specified
- **Path:** from `~/.plastic/config.yml` `project_roots` (first entry as default), or user-specified
- Confirm path with user before creation

### 2. Create Project Directory

```bash
mkdir -p <project_root>/<slug>
cd <project_root>/<slug>
git init
```

### 3. Run `plastic-install --local`

Invoke `plastic-install --local` in the project directory. This creates:
```
.plastic/
├── store/
├── INDEX.md
└── config.yml
```

### 4. Populate AGENTS.md

Create `AGENTS.md` in the project root with:

```markdown
# <Project Name> — Agent Instructions

Read `PLASTIC.md` in `~/.plastic/`. It contains all Plastic conventions.
Follow it exactly.

This file is the operating contract for this project. Any agent entering
this project reads this file first.

## Global Store

Location: `~/.plastic/`
Governing intent(s): <list of founding intent IDs with descriptions>

## Decisions

<Copy ALL decisions from founding intent(s)' `## Context > ### Decisions`>

Each decision should include:
- The decision itself
- The rationale (why this choice)
- Date decided

## Project-Specific Rules

<Any rules derived from the decisions — e.g., "Use Minitest, not RSpec",
"37signals methodology", "sqlite-vec for vector storage">
```

### 5. Create Tactical Mirror

Create the first intent in the project's store at `~/.plastic/projects/{slug}/store/`:

**Directory:** `~/.plastic/projects/{slug}/store/1--{slug}/`
**File:** `~/.plastic/projects/{slug}/store/1--{slug}/1--{slug}.md`

```yaml
---
id: '1'
intent: "<same description as founding intent>"
sources: ["global:<founding_intent_ID>"]
chain: []
created: <today>
author: <same as founding intent author>
tags: [<relevant tags>]
---
```

Sections:
- `## Intent` — same as founding intent
- `## Context` — carry forward relevant Context and Decisions
- `## Outcome` — (pending)
- `## Insights` — empty
- `## Links` — `[[global:<founding_intent_ID>|<founding intent name>]]`

Update the project's `~/.plastic/projects/{slug}/INDEX.md`:
```markdown
# Index

## Active
- [1 — <intent name>](store/1--<slug>/1.md) — implementation, from: global:<ID>
```

**For multi-intent spawning (Hub):**
- `sources`: `["global:<id1>", "global:<id2>", ...]` — all founding intents
- All founding intents' decisions merge into AGENTS.md
- Context carries forward from all founding intents

### 6. Register in projects.yml

Read `~/.plastic/projects.yml` and add:

```yaml
<slug>:
  path: <full-path>
  parent: "<founding_intent_ID>"
  registered: <today>
  status: active
```

For Hub-spawned projects, `parent` references the primary founding intent.

### 7. Mark Global Intent(s) Completed

For each founding intent:

1. Write `## Outcome` in the intent file:
   > "Spawned project `<slug>` at `<path>`. Decisions carried to AGENTS.md. Tactical mirror: `project-<slug>:1`."
2. Write `outcome.md` with full details (all decisions, project path, tactical mirror ID)
3. Update `chain` to include `project-<slug>:1`
4. Move from `## Active` to `## Completed` in `~/.plastic/INDEX.md` (with today's date)

### 8. Framework Scaffolding

If decisions specify a framework, run the appropriate scaffolding command AFTER steps 3-4 (so scaffolding doesn't overwrite Plastic files or AGENTS.md):

| Framework | Command |
|---|---|
| Rails | `rails new <slug> [options from decisions] --skip-git` (skip git — already initialized) |
| Node/npm | `npm init -y` |
| Ruby gem | `bundle gem <slug>` |
| Other | As specified in decisions |

After scaffolding, verify AGENTS.md and `.plastic/` still exist. If scaffolding overwrote them, restore.

### 9. Auto-commit Both Stores

```bash
cd ~/.plastic && git add . && git commit -m "feat: spawn project <slug> from intent <ID>"
cd <project> && git add . && git commit -m "feat: initialize project from intent <ID>"
```

### 10. Register the project store with QMD (optional)

If QMD is installed, register the new project's store as a search collection:

```bash
ruby ~/.plastic/scripts/qmd-sync register --store ~/.plastic/projects/<slug>/store
```

`qmd-sync` no-ops when QMD is absent, so run it unconditionally. This adds the
`plastic-<slug>` collection and indexes it.

### 11. Announce

Log in `## Insights` of each founding intent:
> "Project `<slug>` created at `<path>`. Tactical mirror: `project-<slug>:1` (autonomous)"

Announce to user:
> "Project `<slug>` created at `<path>`. AGENTS.md populated with [N] decisions from [founding intent IDs]. Tactical mirror `1` is now the active intent in the project store."

## References

- Read `references/hubs-projects.md` for the full hub/project relationship model, project creation flow, and cross-linking conventions
