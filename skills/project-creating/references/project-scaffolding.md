# Project Scaffolding Templates

Full templates for the artifacts created while spawning a project: the AGENTS.md
skeleton (Workflow step 4), the tactical mirror intent (step 5), and the
projects.yml registration block (step 6).

## Table of Contents

- [AGENTS.md skeleton (step 4)](#agentsmd-skeleton-step-4)
- [Tactical mirror intent (step 5)](#tactical-mirror-intent-step-5)
- [projects.yml registration block (step 6)](#projectsyml-registration-block-step-6)

## AGENTS.md skeleton (step 4)

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

## Tactical mirror intent (step 5)

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

## projects.yml registration block (step 6)

Read `~/.plastic/projects.yml` and add:

```yaml
<slug>:
  path: <full-path>
  parent: "<founding_intent_ID>"
  registered: <today>
  status: active
```

For Hub-spawned projects, `parent` references the primary founding intent.
