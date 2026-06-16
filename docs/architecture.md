# architecture

## overview

Plastic is an intent store plus a thin tooling layer over it. The store is plain files (folders, Markdown, YAML frontmatter) that capture desires and carry them through a fixed lifecycle; the tooling (skills, hooks, scripts, templates) keeps the store well-shaped and automates the deterministic parts. This document describes the system structure. For how the cycles actually execute (operational mechanics, harness detail), see [internals](internals.md). For the pitch and quick start, see the [README](../README.md).

## the two processes

Plastic runs two processes at once. They are nested, not alternatives: the lifecycle of a single intent runs inside the never-ending loop of the whole system.

### coordinator loop (build, observe, repeat)

The outer heartbeat is **Build, Observe, Repeat (B to O to R)**, driven by the coordinator across the whole system:

- **Build**: advance whatever intent is currently active.
- **Observe**: read what the work surfaced.
- **Repeat**: pick the next thing.

It never ends while the store is in use.

### intent lifecycle (what, why, how, exec)

The inner, finite life of a single intent is **What to Why to How to Exec**:

- **What**: the desire is captured (the intent file with `## Intent` filled).
- **Why**: the desire is justified and decided (`## Context` plus `spec.md`).
- **How**: the work is planned (`plan.md` plus `checklist.md`, optionally `actions/`).
- **Exec**: the work is carried out and the result recorded (`outcome.md` plus the `## Outcome` summary).

Once Exec completes, the intent is done.

### how they connect

Each intent keeps an append-only work log in the `## Insights` section of its intent file. Append-only means newest entry at the bottom, never prepended, so the trace reads in order across every intent. Those insights are exactly what the coordinator reads in its Observe phase to decide what to Build next. The inner lifecycle feeds the outer loop through Insights.

(Footnote: PLASTIC.md is the authority on this wording and defines the outer loop as Build, Observe, Repeat. The README currently labels it "Brainstorm, Organize, Review", which is inconsistent and should be reconciled to match PLASTIC.md.)

## the store layout

A store is a folder of intents. There are two scopes, structurally identical, differing only in location and purpose.

- **Global store** (`~/.plastic/`): one per person, holding strategic intents (personal goals, research, framework work). It also holds person-level configuration: a preferences file (`config.yml`) and a project registry (`projects.yml`).
- **Project stores** (`~/.plastic/projects/{slug}/store/`): one per project, holding tactical intents (concrete work items inside that project). A project store adds one defaults file (`AGENTS.md`) for project-scoped rules.

Each store has exactly one `INDEX.md` and a `store/` folder holding one directory per intent:

```
~/.plastic/
  INDEX.md
  config.yml
  projects.yml
  store/
    ID--slug/

~/.plastic/projects/{slug}/
  INDEX.md
  AGENTS.md
  store/
    ID--slug/
```

The rule of thumb: if the work changes a specific project's code it is tactical and belongs in that project's store; otherwise it is strategic and belongs in the global store. When in doubt, global. Stores are personal and local; the global store is git-tracked locally but never pushed to a remote.

### intent directory contents

Every intent is a folder named `ID--slug/`. Only the intent file is required; every other artifact appears once its lifecycle stage is reached.

```
ID--slug/
  ID--slug.md     # required, the intent file (its base name equals the folder name)
  spec.md         # the Why deliverable
  plan.md         # the How deliverable (planning)
  checklist.md    # the How deliverable (execution registry)
  outcome.md      # the Exec deliverable (its existence signals completion)
  savepoint.md    # deterministic cycle-step ledger, written automatically
  actions/        # individual work items, when work splits into parallel pieces
  resources/      # research, references, snapshots, diagrams
```

Lifecycle artifacts use those exact reserved names and live directly in the intent folder, never in subfolders and never renamed. All other supporting material goes in `resources/`. State is not stored in a status field; it is derived from which files and sections exist (for example, an empty `## Context` means the intent is still fleeting, and the presence of `outcome.md` means it is done).

## identity and the knowledge graph

Intents are addressed by Folgezettel IDs, following Luhmann's alternating convention. Assigning an ID requires only reading the existing IDs in the store:

- **Root intents** are sequential integers: `1`, `2`, `3`. The next root is one greater than the highest existing integer root.
- **Branches alternate number and letter** as they descend from the parent: `1` to `1a` to `1a1` to `1a1a`.
- **Sibling branches increment the final segment**: the first child of `14` is `14a`, then `14b`, then `14c`.

Whether to branch is a meaning decision: branch when the new intent cannot stand on its own without its parent; make it a root when it is independent, even if inspired by another intent (record the provenance in `sources`).

Intents form a double-linked graph, recorded in two mirrored places:

- **Frontmatter** (the machine-followable graph): `sources` are backward links (what influenced this intent) and `chain` are forward links (what this intent spawned). If `B` lists `A` in its `sources`, then `A` should list `B` in its `chain`.
- **Prose** (the human-readable graph): wikilinks under `## Links`, written `[[ID]]` or `[[ID|display text]]`. A tactical intent links back to its governing strategic intent with `[[global:ID]]`.

Each store's `INDEX.md` is a structure note, not a table of contents: it groups intents by meaning and records where each one sits in the person's attention (`## Active`, `## Future`, `## Clusters`, `## Abandoned`, `## Completed`). It does not record lifecycle stage, since that is derived from the files.

## component map

The tooling layer is thin and sits on top of the store. The parts that supply determinism do so by construction, never by judgement.

- **Skills**: the workflows agents follow (creating intents, brainstorming, writing plans, executing, releasing, indexing). They produce the lifecycle artifacts in their fixed forms.
- **Hooks**: lifecycle event handlers. A SessionStart hook detects the active project by matching the working directory; transition gates are enforced by hooks that block (non-zero exit) when a stage's preconditions are not met on the filesystem. Deterministic by construction.
- **Scripts**: small deterministic Ruby programs that encode mechanical rules, for example assigning the next Folgezettel ID from the existing IDs in a store. Deterministic by construction.
- **Templates**: the fixed FORM of each artifact (its sections, their order, frontmatter fields, file name). Two people following the same template produce artifacts of identical shape even when the words differ. Deterministic by construction.
- **Evals**: checks that verify skills produce convention-compliant output and that descriptions trigger correctly.

For the operational detail behind these parts (determinism coverage, harness taxonomy, upgrade backlog), see [internals](internals.md).

## session boot

Resuming a session is a fixed sequence run by the `plastic-continuing` skill, in this order:

1. **Core doctor**: a fast runtime-liveness check (`doctor.rb --core`) runs first and prints one health line, so a broken runtime surfaces before any state is loaded on top of it.
2. **Load core**: prime the conventions (PLASTIC.md and the harness docs), read the store INDEX.md and projects.yml, detect the current project by matching the working directory, and load that project's state.
3. **Version and statusline**: print the installed version and set the statusline.
4. **Dashboard**: invoke the project dashboard when a project is loaded, otherwise the global dashboard. The skill only invokes the renderer, it does not render.

The skill then stops and presents choices. It does not drive work autonomously (that is `plastic-auto`). When the user or an agent asks to continue a specific intent, the skill reads that intent's `savepoint.md` ledger (last line is the current stage), verifies the named stage file exists, rebuilds the ledger on drift, and derives the next step from the first unchecked checklist item.
