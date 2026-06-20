# Building an Intent — Full Lifecycle Detail

## What → `## Intent` section

The desire. One paragraph. What the human or agent wants.
This exists from the moment the intent is created.

**Deliverable:** `{ID}--{slug}.md`

## Why → `## Context` + `### Decisions` sections

Why this intent exists. Grows over time through brainstorming and exploration.

- **Context** — what we knew going in + what we decided along the way
- **Decisions** — main premises derived from Context plus decisions from brainstorming/grilling
- Decisions are Why-level: "status belongs on actions because multiple workstreams", not How-level: "use ACTION_N.md files"

**Deliverable:** `spec.md` (consolidated specification from Context + Decisions + brainstorming)

## How → Planning and preparation

Research decisions, create the implementation plan, define actions.

**Deliverable:** `plan.md` + `actions/` + `checklist.md` (execution registry with checkboxes covering all actions)

## Exec → Execute actions

Execute actions from the plan, track progress via checklist.

**Deliverable:** `outcome.md` (detailed result). `## Outcome` in intent.md = short summary written as last step.

## `## Insights` — Append-only work log

Captured throughout ALL stages. One-liner bullet points.
Never modified, only appended.

Tracks: stage transitions, decisions, shifts, blocks, cancellations, material for future intents.
This is how execution is tracked. When this intent completes, Insights
is where to look for what comes next. New intents spawned from this one,
plus related-but-not-spawned successors it leads to, appear in the `chain`
field.

## `## Links`

The human-readable projection of the local knowledge graph: all `sources`
first (top, named), then all `chain` (named), as `[[id]]` wikilinks plus a
short label. Counterpart to the frontmatter `sources` / `chain` edges, for
Obsidian graph navigation.

## Conventions — Filesystem as Schema

State is derived from what exists, not from what's declared.

| Convention | Signal |
|---|---|
| No `## Context` | Intent is fleeting (quick capture, non-actionable) |
| `## Context` has content | Intent is permanent (developed, actionable) |
| `## Outcome` has content | Intent is done |
| `## Insights` has `(autonomous)` entries | Intent is/was being delivered autonomously |

### Transitions

- Fleeting → permanent: add `## Context` (one-way, also makes it actionable)
- There is no separate "non-actionable → actionable" transition — permanence implies actionability
- Even research intents are actionable: the research itself is the action, the conclusion is the outcome

## Creating an Intent — Full Steps

1. Determine the target store: `~/.plastic/store/` for global intents (default), `~/.plastic/projects/{slug}/store/` for project intents
2. Decide branch vs root (this sets whether you pass `--parent`)
3. Scaffold with one call: `"${CLAUDE_PLUGIN_ROOT}/scripts/new-intent" --store <store> --intent "<one-line>" --slug <slug> [--parent <id>] [--sources id,id] [--tags ...]`. This allocates the id, creates the directory plus `actions/` and `resources/`, renders the born-complete intent file (frontmatter plus `## Intent`, `## Context`, `## Outcome`, `## Insights`, `## Links`), writes the sentinel placeholder lifecycle files, wires the reciprocal links, and self-validates.
4. Update the appropriate `INDEX.md` — add to Active section and appropriate cluster

The intent file is born complete with all five sanctioned `##` sections; the lifecycle files (`spec.md`/`plan.md`/`checklist.md`/`outcome.md`) are sentinel placeholders that read as "stage not reached" until an agent fills them and deletes the `<!-- plastic:placeholder -->` first line.

Always scaffold through `new-intent` (or this skill). Never hand-author intent files: the write-time create gate blocks an incomplete or malformed intent file, and hand-authoring is the bypass this contract is designed to remove.
