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
- **Agents**: role files shipped in `agents/` that the installer syncs into each harness agent directory (Claude, codex, hermes) and tracks in that harness's manifest, so they prune on update and uninstall cleanly. In auto mode they form a 5-role enforcer-led team (one team per intent): brainstorming, spec-specialist, planner, executor, and a plastic-enforcer that orchestrates the others and owns every gate. See `skills/auto/references/agent-architecture.md` for the team model.
- **Hooks**: lifecycle event handlers. A SessionStart hook detects the active project by matching the working directory; transition gates are enforced by hooks that block (non-zero exit) when a stage's preconditions are not met on the filesystem. Deterministic by construction.
- **Scripts**: small deterministic Ruby programs that encode mechanical rules, for example assigning the next Folgezettel ID from the existing IDs in a store. Deterministic by construction.
- **Templates**: the fixed FORM of each artifact (its sections, their order, frontmatter fields, file name). Two people following the same template produce artifacts of identical shape even when the words differ. Deterministic by construction.
- **Evals**: checks that verify skills produce convention-compliant output and that descriptions trigger correctly.

For the operational detail behind these parts (determinism coverage, harness taxonomy, upgrade backlog), see [internals](internals.md).

### qmd search integration

QMD is an optional, recommended local markdown search engine layered over the stores. Plastic functions without it (ripgrep over the store files is the fallback), so the integration adds search without becoming a dependency. The topology is one collection per store in the default qmd index, all `plastic-` prefixed: `plastic-global` for the global store and `plastic-<slug>` for each project store (slugs from `projects.yml`). Plastic delegates all index mechanics to the qmd CLI through a single helper (`scripts/lib/qmd_sync.rb`, exposed as the `scripts/qmd-sync` CLI) and never reimplements qmd commands. Index mutation is tied to lifecycle events only, never ad-hoc: install registers all stores, project creation registers the new project store, and intent delivery reindexes the delivering store's collection. Session start is report-only and never mutates the index. Query craft itself is owned by the installed `qmd` skill, not by Plastic.

A `qmd-search` hook on `UserPromptSubmit` makes the search layer get used instead of relying on agent discipline. When qmd is on PATH and the prompt is substantive, it runs a read-only `qmd search` (BM25, no embeddings) over the current project's collection plus `plastic-global`, injects only hits scoring above a threshold as related or prior intents to check before treating the request as new work, and always appends a terse reminder to query qmd when gathering intent context (sources and chain) before falling back to grep or Read. It is a silent no-op when qmd is absent, bounded by a short timeout so a slow qmd never blocks the turn. The decision logic lives in `scripts/lib/qmd_hook.rb` (pure, dependency-injected); the search itself is `QmdSync.search` (read-only, never mutates the index).

### intent born-complete validation

A single validator library, `scripts/lib/intent_validator.rb`, defines whether an intent is born complete (every required frontmatter field present, and `sources` and `chain` well-formed arrays of id references (bare ids, or cross-store references like global:1a2)). It is the only definition of that contract. It is exposed as the `scripts/validate-intent` CLI (exit 0 when complete, non-zero with a report otherwise) and consulted by both the `plastic-creating-intent` skill (a self-verify step after the write) and doctor (the `frontmatter_fields` and `frontmatter_valid` conventions checks). Intents are created only through `plastic-creating-intent` and never hand-authored, so completeness rests on machinery rather than on agent discipline.

### project store provisioning

Project store creation has a single source of truth: the `scripts/provision-project-store` verb, backed by `scripts/lib/store_provisioning.rb`. It is pure filesystem and idempotent: it makes the store directory at `~/.plastic/projects/{slug}/store`, then writes, only if missing, `.gitkeep`, `INDEX.md` (from `templates/index.md`), and `project.yml` (from `templates/project.yml`). It requires the project to already be registered in `projects.yml` (an unregistered slug exits non-zero and creates nothing) and performs no qmd mutation, so any caller (including a doctor fix) stays deterministic. The `plastic-creating-intent` and `plastic-creating-project` skills call it instead of an inline `mkdir`, and `plastic-add-project-store` adds a store to an already-registered project and then runs the separate optional `qmd-sync register` step. Doctor's additive `project_store_dir` check warns (fixable) when a registered project's store directory is missing, naming `provision-project-store {slug}` as the fix.

## session boot

Boot is owned by hooks, so it runs by construction on every session start, not as prose a skill follows (intent 36a):

1. **Core doctor**: `hook-session-start` runs `doctor.rb --core` in-process, reusing the `Doctor` class so there is one source of truth for core health. The core check is binary (pass or error, never warn): it compares every core file against the SHA256 recorded in the install manifests (`~/.plastic/manifest.json` for global scripts and PLASTIC.md; `~/.claude/plastic/manifest.json` for agent-side files), and also confirms hooks are registered, scripts are executable, and the installed version matches.
2. **Load core**: the same hook primes the conventions (PLASTIC.md), reads the store INDEX.md and projects.yml, detects the current project by matching the working directory, and loads that project's state.
3. **Boot banner and version**: the result of the core check drives a binary banner. On pass: `Plastic Core loaded — v{version} | doctor --core run: success`. On error: `Plastic Core loaded — v{version} | doctor --core run: error — run /plastic-doctor`. The banner is emitted on both the `hookSpecificOutput.additionalContext` channel (model-facing) and the top-level `systemMessage` channel (visible in the user's terminal). One `BootBanner` renderer feeds both channels so they cannot drift (intent 54). The hook never blocks (always exits 0).
4. **Statusline**: the always-on `plastic-statusline` StatusLine hook sets the statusline (a distinct hook event that cannot be set from SessionStart).

The `plastic-continuing` skill then continues work: it lands on the dashboard (the project board when a project is loaded, otherwise the global board, invoking the renderer rather than rendering itself), presents choices, and stops. It does not run the health check, load core, or set the statusline, all of which the hooks already did. It does not drive work autonomously (that is `plastic-auto`). When the user or an agent asks to continue a specific intent, the skill reads that intent's `savepoint.md` ledger (last line is the current stage), verifies the named stage file exists, rebuilds the ledger on drift, and derives the next step from the first unchecked checklist item.

## the session bridge and the gate hooks

The gate hooks share a session bridge: a small JSON file under `/tmp` that records the active intent and whether auto mode is armed. Resolving which bridge to use has a fixed precedence (intent 52). Claude Code does not export `CLAUDE_SESSION_ID` into the hook environment; it passes `session_id` on the hook stdin JSON. So the bash wrappers parse `session_id` out of stdin (in Ruby, never in bash) and pass it to the gate scripts. The resolver then picks the first non-empty of three sources, in order: the stdin `session_id`, the `CLAUDE_SESSION_ID` environment variable, and a derived `auto-<digest>` key (a short hash of the store path plus the intent id). The derived key is deterministic, so a session-less arm and a later session-less check land on the same bridge file rather than writing a null-session bridge. A null session can never be persisted.

The savepoint ledger is decoupled from this resolution. The `gate-check` hook derives the intent directory directly from the written file path (it walks up to the first ancestor that looks like `.../store/ID--slug`) and appends the savepoint there before any bridge lookup. A missing bridge, an unset session, or a headless background run no longer skips the ledger. Bridge discovery itself is also tighter: it prefers an exact-session match, then scans the `/tmp` bridges keeping only valid ones, prefers auto-armed bridges, then those whose store matches the working directory, and breaks ties by newest file. To keep that scan cheap, arming and disarming an auto run also purge stale bridge files, so the `/tmp` directory does not accumulate dead bridges over time (intent 67). The bridge is ephemeral live-session state and not a continuation source (a paused intent resumes from its savepoint ledger), so the purge is purely age-based: it keeps the current bridge and anything written in the last 48 hours, and removes everything older regardless of arm state.

## dashboard

The dashboard is the work cockpit. It answers three questions: where we are (recently worked), where we go next (a Value by Effort matrix), and how to conduct each item (a disposition). The split keeps determinism while reaching a Markdown UI:

- **Heavy script, mechanical fill**: `dashboard.rb --data [continue|project <slug>]` emits one complete JSON payload (recently worked, the full matrix with per line glyphs, counts, project summaries). The `plastic-dashboard` skill fills a Markdown template from that payload with near zero reasoning and presents the filled board in its reply. Same store state gives the same payload regardless of model.
- **Markdown surface**: the board is Markdown because the user's UI renders Markdown natively but collapses raw tool-call stdout. Templates live in the skill's `templates/` directory (`dashboard-global.md`, `dashboard-project.md`). The matrix is a small table holding only the quadrant signature and count, with each quadrant's intents printed below it as glyph led lines (the glyph is the bullet, never a Markdown dash, never an HTML break).
- **Entry flow**: the global board lists recently worked across all scopes, a matrix of global intents only, and a summary of the last five projects (counts plus last accessed). The board is the menu: the user replies in free prose with an intent id, a project name (which re-runs the script for that project), or a request to start something new. No capped multiple choice picker.
- **Heuristics**: value is high for an explicit `value: high` field, a human authored root, an intent with a non-empty chain, or an intent that is a source of another. The `unblocked` flag fires only when a future intent has all of its sources done, and `stale` only on aging future intents, so flags stay low noise.
- **Auto-mode contract**: `--json` still emits the machine readable manifest (`dispatchable_queue`, `human_only`, `next_big_thing`) that `plastic-auto` consumes. The plain text modes remain for a raw terminal.
