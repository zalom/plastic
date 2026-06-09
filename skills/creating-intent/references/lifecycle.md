# Building an Intent — Full Lifecycle Detail

## What → `## Intent` section

The desire. One paragraph. What the human or agent wants.
This exists from the moment the intent is created.

**Deliverable:** `{ID}--{slug}.md`

## Why → `## Context` + `### Decisions` sections

Why this intent exists. Grows over time through brainstorming and exploration.

- **Context** — what we knew going in + what we decided along the way
- **Decisions** — main premises derived from Context plus decisions from brainstorming/grilling
- Decisions are Why-level: "status belongs on actions because multiple workstreams",
  not How-level: "use ACTION_N.md files"

**Deliverable:** `spec.md` (consolidated specification from Context + Decisions + brainstorming)

## How → Planning and preparation

Research decisions, create the implementation plan, define actions.

**Deliverable:** `plan.md` + `actions/` + `checklist.md` (execution registry with checkboxes
covering all actions)

## Exec → Execute actions

Execute actions from the plan, track progress via checklist.

**Deliverable:** `outcome.md` (detailed result). `## Outcome` in intent.md = short summary
written as last step.

## `## Insights` — Append-only work log

Captured throughout ALL stages. One-liner bullet points.
Never modified, only appended.

Tracks: stage transitions, decisions, shifts, blocks, cancellations, material for future intents.
This is how execution is tracked. When this intent completes, Insights is where to look for
what comes next. New intents spawned from Insights appear in the `chain` field.

## `## Links`

Wikilinks for Obsidian graph navigation. Human-facing counterpart to the
frontmatter knowledge graph.

## Progressing an Intent

1. **What → Why:** Brainstorm, explore, grill. Add Context + Decisions to `## Context`. Write `spec.md`.
   - **Autonomous handoff:** When Why is complete, human can invoke `plastic:auto` to hand off How and Exec.
2. **Why → How:** Research decisions, plan. Write `plan.md`, create `actions/`, write `checklist.md`.
3. **How → Exec:** Execute actions, update `checklist.md`. When all done, write `outcome.md`.
4. **Throughout:** Capture observations in `## Insights` (append-only). These spark future intents.
5. **Completing:** Write `## Outcome` summary in intent.md. Spawn follow-up intents from `## Insights`, update `chain`.

## Creating an Intent — Full Steps

1. Determine the target store: `~/.plastic/store/` for global intents (default),
   `~/.plastic/projects/{slug}/store/` for project intents
2. Determine the Folgezettel ID: If root (no parent), find highest root number +1.
   If branch, run `"${CLAUDE_PLUGIN_ROOT}/scripts/folgezettel-id" <parent_id> <store_path>`
3. Create the intent directory in the chosen store (e.g., `ID--three-to-five-words`)
4. Create `{ID}--{slug}.md` with frontmatter (id, intent, sources, chain, created, author, tags)
5. Write `## Intent` — the What
6. Add remaining sections: `## Context`, `## Outcome`, `## Insights`, `## Links`
7. Update the appropriate `INDEX.md` — add to Active section and appropriate cluster

A fleeting intent can skip `## Context` — just `## Intent` and empty sections.

## Authorship

Intents can be created by humans or AI agents (`author` field):
`human`, `claude-code`, `hermes`, `openclaw`, or any agent identifier.
