# Plastic — Conventions

> **This file is maintained by Plastic.** It will be overwritten when the
> plugin is updated. Do not modify — your changes will be lost.
> For project-specific rules, use `AGENTS.md` instead.


## What is an Intent

An intent is a directory in the store containing `intent.md` and optional supporting files.
It represents a desire — something a human or agent wants to accomplish, explore, or understand.

```
store/
  NNN--three-to-five-words-XXXXXX/
    intent.md          # required — the intent itself
    spec.md            # optional — consolidated specification (Why deliverable)
    plan.md            # optional — implementation plan (How deliverable)
    checklist.md       # optional — execution registry with checkboxes (How deliverable)
    outcome.md         # optional — detailed result (Exec deliverable)
    actions/           # optional — makes the intent actionable
      ACTION_1.md
    savepoint.md       # optional — session state for resuming
```

## Frontmatter

Identity and knowledge graph only. Nothing operational.

```yaml
---
id: "032"
intent: "Short description of the desire"
sources: ["031"]       # backward links — what influenced this intent's creation
chain: ["033", "034"]  # forward links — what this intent spawned
created: 2026-05-29
author: human          # human | agent-name
tags: [plastic, architecture]
---
```

- `sources` and `chain` form the double-linked knowledge graph
- `sources` = what fed into this intent (parents, inspirations, prerequisites)
- `chain` = what this intent produced (children, follow-ups, spin-offs)
- No other fields. Everything else is derived from conventions.

## Two Processes

Plastic has two nested processes:

| Process | Scope | Type | Actor |
|---|---|---|---|
| **Build → Observe → Repeat** | The system | Continuous loop | Coordinator |
| **What → Why → How → Exec** | One intent | Finite lifecycle | Agent |

**Build → Observe → Repeat** is the Coordinator's heartbeat:
- **Build** — dispatch an intent to an Agent
- **Observe** — review results, read Insights, assess what spawns next
- **Repeat** — create new intents from Insights, dispatch again

**What → Why → How → Exec** is what happens inside each dispatched intent (see Building an Intent below).

The connection point: an intent's **## Insights** (captured throughout all stages) feeds into the Coordinator's **Observe** phase, which triggers a new **Build**. The B→O→R loop never ends; the W→W→H→E lifecycle does.

## Building an Intent — The What→Why→How→Exec Lifecycle

Every intent progresses through four stages. Each stage has a deliverable.

### What → `## Intent` section

The desire. One paragraph. What the human or agent wants.
This exists from the moment the intent is created.

**Deliverable:** `intent.md`

### Why → `## Context` + `### Decisions` sections

Why this intent exists. Grows over time through brainstorming and exploration.

- **Context** — what we knew going in + what we decided along the way
- **Decisions** — main premises derived from Context plus decisions from brainstorming/grilling
- Decisions are Why-level: "status belongs on actions because multiple workstreams", not How-level: "use ACTION_N.md files"

**Deliverable:** `spec.md` (consolidated specification from Context + Decisions + brainstorming)

### How → Planning and preparation

Research decisions, create the implementation plan, define actions.

**Deliverable:** `plan.md` + `actions/` + `checklist.md` (execution registry with checkboxes covering all actions)

### Exec → Execute actions

Execute actions from the plan, track progress via checklist.

**Deliverable:** `outcome.md` (detailed result). `## Outcome` in intent.md = short summary written as last step.

### ## Insights — Append-only work log

Captured throughout ALL stages. One-liner bullet points.
Never modified, only appended.

Tracks: stage transitions, decisions, shifts, blocks, cancellations, material for future intents.
This is how execution is tracked. When this intent completes, Insights
is where to look for what comes next. New intents spawned from Insights
appear in the `chain` field.

### ## Links

Wikilinks for Obsidian graph navigation. Human-facing counterpart to the
frontmatter knowledge graph.

## Conventions — Filesystem as Schema

State is derived from what exists, not from what's declared.

| Convention | Signal |
|---|---|
| `## Context` has content | Intent is permanent (not fleeting) |
| `actions/` directory exists | Intent is actionable |
| `spec.md` exists | Why phase complete |
| `plan.md` + `actions/` + `checklist.md` exist | How phase complete |
| `outcome.md` exists | Intent is done |
| No `## Context` | Intent is fleeting (quick capture, not yet developed) |
| No `actions/` | Intent is non-actionable (research, exploration, idea) |

### Transitions

- Fleeting → permanent: add `## Context` (one-way)
- Non-actionable → actionable: create `actions/` directory (one-way)
- Fleeting intents cannot be actionable — develop the Why before the How

### Actions

When an intent becomes actionable, create `actions/` with:
- `ACTION_N.md` — individual work items
- `CHECKLIST.md` — execution registry tracking progress

Status lives on actions, not on the intent. An intent can have multiple
parallel workstreams.

## State System

Global mode (default):

```
~/.plastic/                               # Global intent store
├── AGENTS.md                             # This file — conventions contract
├── config.yml                            # User preferences
├── projects.yml                          # Project slug → path registry
├── INDEX.md                              # Brain's entry point
└── store/
    └── NNN--three-to-five-words-XXXXXX/  # One directory per strategic intent
        ├── intent.md                     # The intent (always present)
        ├── spec.md                       # Consolidated specification (optional — Why deliverable)
        ├── plan.md                       # Implementation plan (optional — How deliverable)
        ├── checklist.md                  # Execution registry with checkboxes (optional — How deliverable)
        ├── outcome.md                    # Detailed result (optional — Exec deliverable)
        └── savepoint.md                  # Session state for resume (optional)
```

Per-project tactical store (optional, for sub-tasks within a project):

```
<project>/.plastic/
├── store/                                # Project-scoped intents
├── INDEX.md                              # Project-scoped index
└── config.yml                            # Project-scoped config (overrides global)
```

Legacy per-project mode (fallback when no global install exists):

```
<project>/.plastic/                       # Replaces ~/.plastic/ entirely
├── config.yml
├── INDEX.md
└── store/
    └── NNN--three-to-five-words-XXXXXX/
        └── ...
```

### Directory Naming

Format: `NNN--three-to-five-words-XXXXXX` — applies to all stores.
- `NNN` — zero-padded sequential number (scoped within its store)
- `three-to-five-words` — human-readable slug (3-5 words max)
- `XXXXXX` — 6-char deterministic hash (SHA-256 → base36, Ruby stdlib)

### Wikilink Conventions

| Syntax | Meaning |
|--------|---------|
| `[[NNN-HASH]]` | Link to intent in same store |
| `[[global:NNN-HASH]]` | Link to intent in `~/.plastic/store/` |
| `[[project-slug:NNN-HASH]]` | Link to intent in a project's `.plastic/store/` |

### Authorship

Intents can be created by humans or AI agents (`author` field): `human`, `claude-code`, `hermes`, `openclaw`, or any agent identifier.

## INDEX.md — Structure Note

INDEX.md is a Zettelkasten structure note, not a table of contents.
It clusters intents by meaning, not by date or status.

Sections: `## Active`, `## Future`, `## Clusters`, `## Abandoned`, `## Completed`.

## Creating an Intent

1. Determine the target store: `~/.plastic/store/` for strategic intents (default), `<project>/.plastic/store/` for project-tactical intents
2. Scan the target store directory for the next sequential ID
3. Generate hash: `"${CLAUDE_PLUGIN_ROOT}/scripts/hash-intent" "intent name"`
4. Create the intent directory in the chosen store
5. Create `intent.md` with frontmatter (id, intent, sources, chain, created, author, tags)
6. Write `## Intent` — the What
7. Add remaining sections: `## Context`, `## Outcome`, `## Insights`, `## Links`
8. Update the appropriate `INDEX.md` — add to Active section and appropriate cluster

A fleeting intent can skip `## Context` — just `## Intent` and empty sections.

## Progressing an Intent

1. **What → Why:** Brainstorm, explore, grill. Add Context + Decisions to `## Context`. Write `spec.md`.
2. **Why → How:** Research decisions, plan. Write `plan.md`, create `actions/`, write `checklist.md`.
3. **How → Exec:** Execute actions, update `checklist.md`. When all done, write `outcome.md`.
4. **Throughout:** Capture observations in `## Insights` (append-only). These spark future intents.
5. **Completing:** Write `## Outcome` summary in intent.md. Spawn follow-up intents from `## Insights`, update `chain`.

## Context Management (Start-Save-Continue)

### Save Point
Triggered by PreCompact hook or manually:
1. Find active intent(s) from `~/.plastic/INDEX.md`
2. Update active intent's `checklist.md` (check off completed items)
3. Update active intent's `savepoint.md` (in-progress, next steps, blockers, discoveries)
4. Add observations to `## Insights`
5. Update INDEX.md
6. Commit: `cd ~/.plastic && git add . && git commit -m "chore: savepoint — [intent name]"`
7. Notify user to `/clear`

### Continue
Triggered by UserPromptSubmit hook when user says "continue". Priority order:

**1. Active intents first (resume work):**
1. Read INDEX.md → find active intent(s)
2. Read active intent's `intent.md` → what and why
3. Read active intent's `savepoint.md` → where we left off
4. Read active intent's `checklist.md` → what's next
5. Announce: intent name, current state, next step, blockers
6. Resume

**2. No active intents → offer future intents:**
1. List all future intents from INDEX.md
2. Present them as options
3. When user picks one, move to Active in INDEX.md

**3. Stale future intents (untouched 3+ days) → triage:**
- **activate** — start working on it now
- **abandon** — mark as abandoned
- **defer to agent** — implement, research, or ideate

## Rules for Skills

ALL work flows through intents. No skill, agent, or workflow creates directories, specs, plans, or artifacts outside the intent system.

1. **Before starting any work**, check INDEX.md for the active intent. If none exists, create one first.
2. **Never create** `docs/superpowers/specs/`, `docs/plans/`, `researches/`, or similar directories. All artifacts go into the active intent's directory.
3. **When a skill produces output** (spec, plan, checklist), write it inside the active intent's directory.
4. **When a skill completes**, capture observations in `## Insights`.
5. **When work is done**, write `outcome.md` and `## Outcome` summary in intent.md (presence of `outcome.md` = done). Update INDEX.md.
6. **Researches are intents.** No separate folder.

### Delegation to External Skills

When Plastic delegates to an external skill, **Plastic's directory rules OVERRIDE the external skill's defaults:**

- Plans save to `~/.plastic/store/NNN--slug-XXXXXX/plan.md` (not `docs/superpowers/plans/`)
- Specs save to `~/.plastic/store/NNN--slug-XXXXXX/spec.md` (not `docs/superpowers/specs/`)
- Code files go in the project tree; meta-artifacts go in the intent directory

**The rule is simple:** code goes in the project. Plans, specs, checklists, savepoints, and all meta-artifacts go in the intent directory. No exceptions.

## Projects

A Project is a deliverable grouping of intents — a hub that connects related work into something that can be delivered. Projects have two stores:

- **Global store** (`~/.plastic/store/`): strategic intents — ideas, research, explorations, project-spawning hub intents. These never move.
- **Project store** (`<project-path>/.plastic/`): tactical intents — implementation, actions, execution, delivery artifacts. Self-contained.

If a project has no configured codebase path, the fallback location is `~/.plastic/projects/<name>/.plastic/`.

Project membership is expressed via `project-<name>` tags on intents (convention, grepable). The global INDEX.md clusters are the visual representation of project hubs.

`projects.yml` maps project names to codebase paths and is the registry the Coordinator reads to find projects:
```yaml
projects:
  plastic:
    path: "/path/to/plastic"
    remote: "git@github.com:org/plastic.git"
    registered: '2026-05-26'
    status: active
```

Config resolution: project `.plastic/config.yml` overrides global `~/.plastic/config.yml` — like Rails environments override application config.

Cross-linking: tactical intents in the project store reference global hub intents via `sources`. Global hub intents reference the project's tactical intents via `chain`.

## Agent Architecture

One Coordinator per Plastic store. The Coordinator orchestrates all work.

Rules:
- 1 Coordinator : 1 Store (the global `~/.plastic/`)
- 1 Coordinator : N Agent Teams (one per project being worked on)
- 1 Agent : 1 Intent (exclusive assignment)
- 1 Agent : N Sub-agents (for parallel Actions within an intent)

The Coordinator can be any agent platform: Claude Code, Hermes, OpenClaw.
Agents and sub-agents can also be any platform.

Two modes:
- **Human-driven:** Human chats with Coordinator, creates intents, brainstorms, then Coordinator dispatches Agents for execution.
- **Autonomous:** Human gives Coordinator a starting intent with defined outcomes. Coordinator runs the full cycle — Agents do the lifecycle (What→Why→How→Exec), Coordinator reviews Insights, spawns next intents, dispatches again. Human is the boss but doesn't need to be in the loop for every decision.

When "work on Project X":
1. Read `projects.yml` → find project path
2. Load global config (defaults)
3. Load project config (overrides)
4. Load global INDEX.md → find hub intents tagged `project-<name>`
5. Load project `.plastic/INDEX.md` → tactical intents
6. Coordinator has full picture, dispatches Agent teams

The Coordinator runs **Build → Observe → Repeat**:
1. **Build** — dispatch intent to an Agent
2. **Observe** — Agent completes, Coordinator reads ## Insights and ## Outcome
3. **Repeat** — spawn new intents from Insights, update chain, dispatch next

Each Agent runs **What → Why → How → Exec** on its assigned intent:
1. Receives intent from Coordinator
2. Handles full lifecycle: What→Why→How→Exec
3. Can spawn sub-agents for parallel Actions
4. When done: notifies Coordinator (triggers Observe phase)

## Hook Enforcement

Hooks are the convention enforcement layer. The agent reads PLASTIC.md for understanding; hooks enforce it.

### Bridge File Pattern

`/tmp/plastic-{session}.json` is the hot cache; the filesystem is the authority.
SessionStart rebuilds the bridge file from the filesystem — the bridge is always disposable.

### Gate Taxonomy

| Gate type | Purpose |
|---|---|
| **Pre-flight** | Prerequisites exist? (e.g., spec.md before plan.md) |
| **Revision** | New info invalidated prior work? (e.g., Context changed after spec.md was written) |
| **Escalation** | Blocked items surface to user (e.g., unresolved decision needed) |
| **Abort** | Inconsistent state detected (e.g., outcome.md exists but checklist incomplete) |

### Transition Table

| Transition | Trigger |
|---|---|
| What → Why | `spec.md` written |
| Why → How | `plan.md` + `actions/` + `checklist.md` written (the triplet) |
| How → Exec | `checklist.md` has items to execute |
| Exec → Done | `outcome.md` written |

### Gate Enforcement

| Gate | Blocked action | Required prerequisite |
|---|---|---|
| Pre-flight | Cannot write `plan.md` | `spec.md` must exist |
| Pre-flight | Cannot create `actions/` | `spec.md` must exist |
| Pre-flight | Cannot write `outcome.md` | `checklist.md` must exist with all items checked |
| Revision | Cannot proceed to Exec | Context changed after spec.md — re-derive spec |
| Abort | Cannot complete intent | `outcome.md` exists but checklist has unchecked items |

Hard blocking — hooks exit with code 2 when gates fail.

## Stuck Detection

| Condition | Threshold | Action |
|---|---|---|
| Consecutive gate failures | 3+ | Warning |
| Consecutive gate failures | 5+ | Force savepoint + escalate to user |
| No activity | 5+ min | Warning |
| No activity | 10+ min | Force savepoint + escalate to user |
| Context pressure | 80% | Warning |
| Context pressure | 90% | Force savepoint |

Token tracking is done via transcript parsing — Claude Code hooks do not expose token counts directly.

## Zettelkasten Structure

Plastic implements three Zettelkasten structures:

| Structure | Implementation | Purpose |
|---|---|---|
| Folgezettel (linked list) | `sources` + `chain` in frontmatter | Sequential provenance — what led here, what spawned from here |
| Directed graph (web of notes) | `## Links` with wikilinks | Obsidian graph navigation, human-facing connections |
| Tag-based taxonomy | `tags` in frontmatter | Grouping by topic and project membership (`project-<name>`) |

INDEX.md is a structure note (hub), not a table of contents. It clusters intents by meaning. Project hubs in INDEX.md represent deliverable groupings.

## Dual-Mode

This store works in two modes without modification:
- **Obsidian** (human, offline) — browse, link, write markdown
- **Programmatic** (any agent) — read/write via filesystem operations

No special tooling required for either mode.

## Git Rules

The global store (`~/.plastic/`) is tracked with git locally but **never pushed
to a remote**. It contains sensitive data (intents, decisions, project context).

- `~/.plastic/`: git tracked, **never push**
- Project repos: push only when the user explicitly confirms
- Agent-created repos: **private by default**. When an agent creates a GitHub
  repository (e.g., for a new project), it must be private unless the user
  explicitly requests public. Use `gh repo create --private`.

## Agent-Specific Files

