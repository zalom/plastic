# Plastic — Conventions

> **This file is maintained by Plastic.** It will be overwritten when the
> plugin is updated. Do not modify — your changes will be lost.
> For project-specific rules, use `AGENTS.md` instead.

## What is an Intent

A directory in the store containing `{ID}--{slug}.md` and optional supporting files.
It represents a desire — something a human or agent wants to accomplish, explore, or understand.

```
store/
  ID--three-to-five-words/
    {ID}--{slug}.md       # required — the intent itself
    spec.md               # optional — specification (Why deliverable)
    plan.md               # optional — implementation plan (How deliverable)
    checklist.md          # optional — execution registry (How deliverable)
    outcome.md            # optional — detailed result (Exec deliverable)
    actions/              # optional — individual work items
    resources/            # optional — research, references, screenshots, diagrams
    savepoint.md          # optional — deterministic cycle-step ledger (auto-written)
```

Lifecycle files (`spec.md`, `plan.md`, `checklist.md`, `outcome.md`) have defined
roles. Supporting artifacts that aren't lifecycle deliverables — research reports,
reference docs, external API snapshots, screenshots, diagrams — go in `resources/`.
Name files inside as `{type}--{description}.md` (e.g., `deep-research--gsd-core.md`).

## Frontmatter

Identity and knowledge graph only. Nothing operational.

```yaml
---
id: "4a1"
intent: "Short description of the desire"
sources: ["4a"]        # direct ascendants: intents this was created from
chain: ["4a1a"]        # forward: what this spawned and related successors
created: 2026-05-29
author: human          # human | agent-name
tags: [plastic, architecture]
---
```

- `sources` (formative, must-load, acyclic) and `chain` (forward + relational, lighter,
  may cycle) form the directed knowledge graph. Reciprocity is one-directional: every
  `sources` edge has a reciprocal `chain` entry (I1), but `chain` may carry relational
  entries with no reciprocal `sources` (I2), so the graph is not strictly symmetric.
- Context contract: load `sources` strongly (they are what the intent was built from);
  traverse `chain` lightly for discovery. See
  docs/concepts/how-plastic-sources-and-chains-intents.md for the full model.
- `## Links` (I5) is the human-readable projection of the graph. It mirrors the
  frontmatter exactly: every entry is `- [[id--slug|<target's full intent: text>]]`, a
  clickable `id--slug` wikilink target with the target intent's full `intent:` text as the
  label (cross-store targets render `- [[store:id--slug|<target's full intent: text>]]`).
  Ordering is mandatory: all `sources` first (top), then all `chain`, frontmatter order
  preserved within each group. Sources never appear at the end. No source/chain tags, no
  sub-grouping. An intent with empty `sources` and `chain` carries the empty-state comment.
- IDs use Luhmann's alternating convention: `1` → `1a` → `1a1` → `1a1a`
- Multiple branches increment: `1a`, `1b`, `1c`

## Two Processes

| Process | Scope | Type | Actor |
|---|---|---|---|
| **Build → Observe → Repeat** | The system | Continuous loop | Coordinator |
| **What → Why → How → Exec** | One intent | Finite lifecycle | Agent |

B→O→R is the Coordinator's heartbeat. W→W→H→E is what happens inside each intent.
The connection: an intent's `## Insights` feeds the Coordinator's Observe phase.

## Lifecycle Stages

| Stage | Section | Deliverable | Detail |
|-------|---------|-------------|--------|
| **What** | `## Intent` | `{ID}--{slug}.md` | `plastic-creating-intent` |
| **Why** | `## Context` + Decisions | `spec.md` | `plastic-brainstorming` |
| **How** | Planning | `plan.md` + `actions/` + `checklist.md` | `plastic-writing-plans` |
| **Exec** | Execution | `outcome.md` | `plastic-executing-plan` |

`## Insights` — append-only work log captured throughout ALL stages. **Append-only means
newest entry at the bottom; never prepend.** This ordering is a hard convention: Insights
are the semantic trace of an intent, and a consistent newest-last order keeps that trace
readable across every intent.
For full lifecycle detail, the skills in the Detail column have references/.

`savepoint.md` — a deterministic, append-only ledger of cycle-step milestones (one line per
lifecycle boundary, newest at the bottom), written automatically by the gate hook. It is
sugar on top of the conventions, not a source of truth: state is always derivable from
files-on-disk, and the ledger is rebuildable. It exists so a resuming agent reads the cycle's
succession at a glance (last line = where we are).

## Gotchas

- **Artifacts go in the intent directory.** Never create `docs/plans/`,
  `docs/specs/`, `researches/`, or similar. All meta-artifacts go in
  `~/.plastic/store/ID--slug/` or the project store equivalent.
- **Code goes in the project. Everything else goes in the intent.**
  Plans, specs, checklists, savepoints — all in the intent directory.
- **The global store is never pushed.** `~/.plastic/` is git-tracked locally
  but contains sensitive data. Never push to a remote.
- **Agent-created repos are private by default.** Use `gh repo create --private`.
- **State is derived from what exists.** No `## Context` = fleeting intent.
  `## Context` exists = permanent/actionable. `## Outcome` exists = done.
- **Status lives on actions, not intents.** An intent can have parallel workstreams.
- **`outcome.md` = done.** Presence signals completion. Don't write it until
  checklist is fully checked.
- **Delegation overrides external skill defaults.** When delegating to
  brainstorming, writing-plans, etc., Plastic's directory rules override
  their default output paths.

## Defaults-First

Plastic stands on its own. Skills and agents use Plastic's own defaults; an
external skill (for example `superpowers:*`) is opt-in, never load-bearing.

- **Default to Plastic, delegate by exception.** Name the Plastic-native path as
  the default. Delegate to an external skill only when (a) it is available in the
  harness, or (b) the user explicitly asks for it. A user without that plugin must
  still get the core behavior.
- **Phrase external skills as enhancements.** Write "use Plastic's native X by
  default; if `superpowers:<skill>` is available, or the user prefers it, delegate
  to it" never "delegate to `superpowers:<skill>`" as the only path.
- **Optional dependencies detect then degrade.** `qmd` is the reference shape:
  `scripts/lib/qmd_sync.rb` detects the binary first and every verb no-ops cleanly
  when it is absent (see `scripts/qmd-sync`). Optional CLIs and MCP servers follow
  the same detect-then-skip pattern, so a missing tool never crashes a session.
- **Legitimate hard dependencies are exempt.** Ruby, Node, git, and POSIX tools are
  the cost of running Plastic, not silent coupling. The principle targets accidental
  dependence on external skills doing work Plastic should do itself.

## State System

```
~/.plastic/                            # Global intent store (git, never pushed)
├── INDEX.md                           # Structure note (clusters by meaning)
├── config.yml                         # User preferences
├── projects.yml                       # Project slug → path registry
└── store/                             # Strategic intents
    └── ID--slug/
        └── {ID}--{slug}.md

~/.plastic/projects/{slug}/            # Project-scoped store
├── INDEX.md                           # Project-scoped index
├── AGENTS.md                          # Project stack defaults
└── store/                             # Tactical intents
    └── ID--slug/
```

Project stores derived from `projects.yml`. No files placed in project code
directories. SessionStart hook detects project by matching CWD.

**Privacy:** Plastic is personal. All intent data under `~/.plastic/`. Each
person has their own store. Collaboration through PRs, not shared intents.

## Directory Naming

Format: `ID--three-to-five-words` (all stores).

- Root intents: sequential numbers (`1`, `2`, `3`)
- Branches alternate: `1` → `1a` → `1a1` → `1a1a`
- Intent file matches directory: `1a1--slug/1a1--slug.md`
- Next ID: `"${CLAUDE_PLUGIN_ROOT}/scripts/folgezettel-id" <parent_id> <store_path>`

**Branch vs root — the semantic decision.** The numbering is mechanics; choosing
*whether* to branch is meaning:

- **Branch (`14a`, `14b`)** — a sub-task, refinement, or direct continuation of the
  parent. It cannot stand on its own; it only makes sense as part of the parent's work.
- **Root (`15`, `16`)**: an independent thought, even if inspired by another intent.
  Reserve `sources` for true created-from provenance (intents this was built out of). An
  independent intent merely related to or inspired by another carries NO `sources`; record
  the relation on the PREDECESSOR's `chain` (and mirror it as a
  `[[id--slug|<target's full intent: text>]]` wikilink in `## Links`).
- **Rule of thumb:** if the intent could exist without its parent, it's a root.

## INDEX.md

A Zettelkasten structure note, not a table of contents. Clusters by meaning.

Sections: `## Active`, `## Future`, `## Clusters`, `## Abandoned`, `## Completed`.

For index maintenance, use `plastic-managing-index`.

## Rules for Skills

ALL work flows through intents.

1. Before starting work, check INDEX.md for active intent. If none, create one.
2. Skill output (spec, plan, checklist) goes in the intent directory.
3. On completion, capture observations in `## Insights`.
4. When done, write `outcome.md` + `## Outcome` summary. Update INDEX.md.
5. Researches are intents. No separate folder.
6. Intents are created only via `plastic-creating-intent`. Never hand-author an intent file. The skill self-verifies the written intent with `scripts/validate-intent` before announcing or committing, so every intent is born complete.

## Transition Gates

| Transition | Trigger | Gate |
|---|---|---|
| What → Why | `spec.md` written | — |
| Why → How | `plan.md` + `actions/` + `checklist.md` | `spec.md` must exist |
| How → Exec | Checklist has items | Plan triplet must exist |
| Exec → Done | `outcome.md` written | All checklist items checked |

Hard blocking — hooks exit code 2 on gate failure.

## Deprecation Process

Deprecations live in `deprecations.yml` and are shown at SessionStart. While Plastic is
pre-1.0, a satisfied deprecation (its migration is already done on installed machines) may be
removed immediately instead of waiting for its declared `removal` version. From `1.0.0` on,
the steady-state grace rule applies (removal at least two minors ahead). For the full process,
severity levels, and the pre-1.0 exception, see the `plastic-releasing` skill.

## Skills Reference

Detailed conventions live inside the skills that use them, not in this file.

| Topic | Skill | References in skill |
|-------|-------|-------------------|
| Creating intents, lifecycle | `plastic-creating-intent` | lifecycle, wikilinks |
| Brainstorming, spec writing | `plastic-brainstorming` | — |
| Planning, actions | `plastic-writing-plans` | — |
| Execution, delivery | `plastic-executing-plan` | — |
| Autonomous delivery | `plastic-auto` | agent architecture |
| Save/restore state | `plastic-savepoint`, `plastic-continuing` | context management |
| Knowledge graph, linking | `plastic-linking-intents` | zettelkasten, wikilinks |
| Projects, hubs | `plastic-creating-project` | hubs, project stores |
| Provision a project store | `plastic-add-project-store` | project stores |
| Index maintenance | `plastic-managing-index` | — |
| Releases, deprecations | `plastic-releasing` | deprecation process |
| Health diagnostics | `plastic-doctor` | three scopes: `--core` (binary install-integrity check, runs on SessionStart), `--store [global\|<slug>]` (per-store check, runs on dashboard load), no flag = full check (runs after every update); gate enforcement, stuck detection |
| Writing agent instructions | `plastic-writing-instructions` | agentskills.io spec |
| Evaluating skills, evals | `plastic-evaluating-skills` | eval methodology, convention checks |
