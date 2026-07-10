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
  outcome.md      # the Exec deliverable (mandatory at every terminal; a disposition: delivered|abandoned header)
  savepoint.md    # deterministic cycle-step ledger, written automatically
  revisions.md    # optional structural-maintenance audit trail (present only after maintenance)
  actions/        # individual work items, when work splits into parallel pieces
  resources/      # research, references, snapshots, diagrams
```

Lifecycle artifacts use those exact reserved names and live directly in the intent folder, never in subfolders and never renamed. All other supporting material goes in `resources/`. State is not stored in a status field; it is derived from which files and sections exist (for example, an empty `## Context` means the intent is still fleeting, and the presence of `outcome.md` means it is done). `revisions.md` is not a lifecycle artifact: it appears only when structural maintenance relocated a misplaced section, file, or ref out of a delivered intent, so its existence signals structural (not conceptual) change.

## identity and the knowledge graph

Intents are addressed by Folgezettel IDs, following Luhmann's alternating convention. Assigning an ID requires only reading the existing IDs in the store:

- **Root intents** are sequential integers: `1`, `2`, `3`. The next root is one greater than the highest existing integer root.
- **Branches alternate number and letter** as they descend from the parent: `1` to `1a` to `1a1` to `1a1a`.
- **Sibling branches increment the final segment**: the first child of `14` is `14a`, then `14b`, then `14c`.

Whether to branch is a meaning decision: branch when the new intent cannot stand on its own without its parent; make it a root when it is independent, even if inspired by another intent (record the provenance in `sources`).

Intents form a double-linked graph, recorded in two mirrored places:

- **Frontmatter** (the machine-followable graph): `sources` are backward links (what influenced this intent) and `chain` are forward links (what this intent spawned). If `B` lists `A` in its `sources`, then `A` should list `B` in its `chain`.
- **Prose** (the human-readable graph): wikilinks under `## Links`, written `[[ID]]` or `[[ID|display text]]`. A tactical intent links back to its governing strategic intent with `[[global:ID]]`.

The frontmatter graph drifts over time as it is edited by hand, so two pieces of machinery keep it honest. `scripts/rebuild-graph` is a deterministic, idempotent maintenance tool that repairs the `sources`/`chain` graph across all three stores in one pass: it dedupes each array, enforces the I-invariants one-directionally (a formative edge wins over a duplicate; missing in-store backlinks are added; relational forward links survive), and resolves cross-store refs against a multi-hop relocation map built from every store's `## Relocated` log, so a relocated target is repointed (and collapsed to a bare id when it now lives in the referring store) and a coincidentally-reused id never wins over a recorded relocation. Every change is written to a per-store before/after audit, and a re-run over a repaired store is a no-op. Complementing it, `doctor.rb` carries a `graph_cross_store_resolution` check that resolves every cross-store ref against the full store family (not just shape-checks it), so a well-formed ref pointing at a relocated or deleted intent is caught rather than silently accepted. See [internals](internals.md) for the module split and the named id-reuse hazard.

Each store's `INDEX.md` is a structure note, not a table of contents: it groups intents by meaning and records where each one sits in the person's attention (`## Active`, `## Future`, `## Clusters`, `## Abandoned`, `## Completed`). It does not record lifecycle stage, since that is derived from the files.

## component map

The tooling layer is thin and sits on top of the store. The parts that supply determinism do so by construction, never by judgement.

- **Skills**: the workflows agents follow (creating intents, brainstorming, writing plans, executing, releasing, indexing, and authoring skills, agents, and hooks via `creating-skills`). They produce the lifecycle artifacts in their fixed forms.
- **Agents**: role files shipped in `agents/` that the installer syncs into each harness agent directory (Claude, codex, hermes) and tracks in that harness's manifest, so they prune on update and uninstall cleanly. In auto mode they form a 5-role enforcer-led team (one team per intent): brainstorming, spec-specialist, planner, executor, and a plastic-enforcer that orchestrates the others and owns every gate. See `skills/auto/references/agent-architecture.md` for the team model.
- **Hooks**: lifecycle event handlers. A SessionStart hook detects the active project by matching the working directory; transition gates are enforced by hooks that block (non-zero exit) when a stage's preconditions are not met on the filesystem. A PreToolUse create gate (`hook-create-gate`, matcher Write plus Edit plus the Serena MCP edit tools, intents 60b and 108) blocks a mutation of an intent file that is not born complete or structurally sanctioned: a Write is judged on its proposed content, an Edit on the simulated replacement result, and a pathless MCP edit on the current on-disk file, all independent of any session bridge. Hook registration itself has one source of truth, `scripts/lib/hook_registry.rb`: the installer merge and the plugin `hooks/hooks.json` derive from it, and doctor's `hooks_match_registry` check flags drift. Deterministic by construction.
- **Scripts**: small deterministic Ruby programs that encode mechanical rules, for example assigning the next Folgezettel ID from the existing IDs in a store. Intent creation has a one-call contract here: `scripts/new-intent` allocates the id, creates the directory tree, renders the born-complete intent file, writes the sentinel placeholder lifecycle files, wires the reciprocal links, and self-validates, so the sanctioned path is one CLI call rather than several hand-authored writes (intent 60b). It does not touch INDEX.md, git, or project creation; those stay in the creating-intent skill. Deterministic by construction.
- **Templates**: the fixed FORM of each artifact (its sections, their order, frontmatter fields, file name). Two people following the same template produce artifacts of identical shape even when the words differ. Deterministic by construction.
- **Evals**: checks that verify skills produce convention-compliant output and that descriptions trigger correctly.

For the operational detail behind these parts (determinism coverage, harness taxonomy, upgrade backlog), see [internals](internals.md).

### per-agent models and stage coverage

Every stage of the intent lifecycle has exactly one dispatchable background agent, plus the enforcer that orchestrates them:

| Stage | Agent |
|---|---|
| What | `plastic-intent-discovery` |
| Why | `plastic-brainstorming` + `plastic-spec-specialist` |
| How | `plastic-planner` |
| Exec | `plastic-executor` |
| Done | `plastic-intent-curator` |

Final-gate code review stays an ad-hoc subagent the enforcer dispatches at the final gate, not a standing role.

`plastic-intent-discovery` is the What-stage agent (see the `plastic-intent-discovering` skill): it fires at intent activation, after the delivery lock is armed and before Why begins, running under that lock as the owner session, runs QMD discovery over the intent's `chain`/`sources` and related parked intents, and deposits its findings to `resources/discovery--<slug>.md` only. It never writes the intent file; the Why-stage `plastic-brainstorming` agent reads its deposit and enriches `## Context`.

Every agent in `agents/*.md` pins an explicit Claude Code model alias (`opus` or `sonnet`) in its frontmatter: never `inherit`, never Fable. The tier is by role weight, not by stage:

| Agent | Model |
|---|---|
| `plastic-enforcer`, `plastic-brainstorming`, `plastic-planner` | `opus` |
| `plastic-spec-specialist`, `plastic-executor`, `plastic-intent-curator`, `plastic-future-intent-researcher`, `plastic-intent-discovery` | `sonnet` |

A project or the global store can override any agent's tier through `agents.models.<basename>` config; see [internals](internals.md) for the config precedence and the installer mechanism that applies it. Every dispatch site also resolves and passes the target agent's model explicitly at dispatch time, belt-and-braces on top of the frontmatter pin, since reading frontmatter at dispatch is a harness detail rather than a Plastic-owned contract. At auto-mode start, the orchestrator advises (never gates) that the user run the main session on the best available thinking model for the sharpest synthesis; this is the one context where Fable is named as an acceptable choice, since it concerns the human's session, not a subagent.

### qmd search integration

QMD is an optional, recommended local markdown search engine layered over the stores. Plastic functions without it (ripgrep over the store files is the fallback), so the integration adds search without becoming a dependency. The topology is one collection per store in the default qmd index, all `plastic-` prefixed: `plastic-global` for the global store and `plastic-<slug>` for each project store (slugs from `projects.yml`). Plastic delegates all index mechanics to the qmd CLI through a single helper (`scripts/lib/qmd_sync.rb`, exposed as the `scripts/qmd-sync` CLI, with verbs for detect, register, reindex, status, and a read-only `search`) and never reimplements qmd commands. Index mutation is tied to lifecycle events only, never ad-hoc: install registers all stores, project creation registers the new project store, and intent delivery reindexes the delivering store's collection. That delivery reindex is mandatory on completion and runs async (detached, non-blocking) so it never holds up the turn. Session start is report-only and never mutates the index. Query craft itself is owned by the installed `qmd` skill, not by Plastic.

A power-tools hook on `UserPromptSubmit` keeps the search layer visible instead of relying on agent memory. When qmd is on PATH and the prompt is substantive, it runs a read-only `qmd search` (BM25, no embeddings) over the current project's collection plus `plastic-global` and injects only hits scoring above a threshold as related or prior intents to check before treating the request as new work. Beyond the hits, the hook appends one recommendation line per present tool: "QMD is available: prefer `qmd search` / `qmd query`" whenever qmd is present, plus "Serena is available: prefer its symbolic tools" whenever Serena is present. These are recommendations, not obligations (intent 108, D8); the retrieval gate is advisory and never blocks a read or search. Tool presence is computed by a small power-tools harness (`scripts/lib/power_tools.rb`: `PowerTools.qmd?`, `PowerTools.serena?`, `PowerTools.mandate`), where Serena is detected by a `.serena` marker in the working directory or an ancestor, or `serena` on PATH. It is a silent no-op when neither tool is present, bounded by a short timeout so a slow qmd never blocks the turn. The decision logic lives in `scripts/lib/qmd_hook.rb` (pure, dependency-injected); the search itself is `QmdSync.search` (read-only, never mutates the index). The per-skill QMD-first steps reinforce the same discipline: search qmd first, then open the authoritative intent file, with a no-op fallback when qmd is absent.

### intent born-complete validation

A single validator library, `scripts/lib/intent_validator.rb`, defines whether an intent is born complete (every required frontmatter field present, and `sources` and `chain` well-formed arrays of id references (bare ids, or cross-store references like global:1a2)). It is the only definition of that contract. It is exposed as the `scripts/validate-intent` CLI (exit 0 when complete, non-zero with a report otherwise) and consulted by both the `plastic-intent-creating` skill (a self-verify step after the write) and doctor (the `frontmatter_fields` and `frontmatter_valid` conventions checks). Intents are created only through `plastic-intent-creating` and never hand-authored, so completeness rests on machinery rather than on agent discipline.

### project store provisioning

Project store creation has a single source of truth: the `scripts/provision-project-store` verb, backed by `scripts/lib/store_provisioning.rb`. It is pure filesystem and idempotent: it makes the store directory at `~/.plastic/projects/{slug}/store`, then writes, only if missing, `.gitkeep`, `INDEX.md` (from `templates/index.md`), and `project.yml` (from `templates/project.yml`). It requires the project to already be registered in `projects.yml` (an unregistered slug exits non-zero and creates nothing) and performs no qmd mutation, so any caller (including a doctor fix) stays deterministic. The `plastic-intent-creating` and `plastic-project-creating` skills call it instead of an inline `mkdir`, and `plastic-store-provisioning` adds a store to an already-registered project and then runs the separate optional `qmd-sync register` step. Doctor's additive `project_store_dir` check warns (fixable) when a registered project's store directory is missing, naming `provision-project-store {slug}` as the fix.

## session boot

Boot is owned by hooks, so it runs by construction on every session start, not as prose a skill follows (intent 36a):

1. **Core doctor**: `hook-session-start` runs `doctor.rb --core` in-process, reusing the `Doctor` class so there is one source of truth for core health. The core check is binary (pass or error, never warn): it compares every core file against the SHA256 recorded in the install manifests (`~/.plastic/manifest.json` for global scripts and PLASTIC.md; `~/.claude/plastic/manifest.json` for agent-side files), and also confirms hooks are registered, scripts are executable, and the installed version matches.
2. **Load core**: the same hook primes the conventions (PLASTIC.md), reads the store INDEX.md and projects.yml, detects the current project by matching the working directory, and loads that project's state.
3. **Boot banner and version**: the result of the core check drives a binary banner. On pass: `Plastic Core loaded - v{version} | doctor --core run: success`. On error: `Plastic Core loaded - v{version} | doctor --core run: error - run /plastic-doctor`. The banner is emitted on both the `hookSpecificOutput.additionalContext` channel (model-facing) and the top-level `systemMessage` channel (visible in the user's terminal). One `BootBanner` renderer feeds both channels so they cannot drift (intent 54). The hook never blocks (always exits 0).
4. **Statusline**: the always-on `plastic-statusline` StatusLine hook sets the statusline (a distinct hook event that cannot be set from SessionStart). This is the render-time behavior once Plastic's statusline is configured; whether it gets configured at all is an install-time decision (see below).

Install-time statusline choice is separate from the render-time hook above: `InstallerCore#statusline_choice` decides, once per install, whether to write Plastic's statusline over an existing one. A fresh settings file with no statusline gets Plastic's line with no prompt. An existing non-Plastic line triggers a keep-or-switch prompt in an interactive session, honors `--statusline keep|plastic` to skip the prompt, defaults to keeping the user's line in a non-interactive session, and is never re-asked on `--reinstall` (a repair keeps whatever is already configured). `merge_claude_hooks` still backs up the prior line to `~/.plastic/.cache/original-statusline.json` regardless of the choice, so a later switch or an uninstall can restore it.

The `plastic-intent-continuing` skill then continues work: it lands on the dashboard (the project board when a project is loaded, otherwise the global board, invoking the renderer rather than rendering itself), presents choices, and stops. It does not run the health check, load core, or set the statusline, all of which the hooks already did. It does not drive work autonomously (that is `plastic-auto`). When the user or an agent asks to continue a specific intent, the skill reads that intent's `savepoint.md` ledger FIRST (intent 81): the last line classifies the state (a cycle position, or `Done delivered|abandoned` for a terminal intent), and it verifies only that last line's artifact before continuing, rebuilding the ledger from files on drift. The ledger's fixed bookends, a born `What created` first line and a `Done` last line, make state a single read instead of a filesystem probe.

## the session bridge and the gate hooks

The gate hooks share a session bridge: a Hash that records the active intent and whether auto mode is armed. Since intent 41, this state lives in the store's `plastic.db` (the `sessions` table), not a `/tmp` JSON file; see [the operational database layer](#the-operational-database-layer) below for the storage mechanism. Resolving which session row to use has a fixed precedence (intent 52). Claude Code does not export a session id env var into the hook environment; it passes `session_id` on the hook stdin JSON. So the bash wrappers parse `session_id` out of stdin (in Ruby, never in bash) and pass it to the gate scripts. The resolver then picks the first non-empty of: the stdin `session_id`, the `CLAUDE_CODE_SESSION_ID` environment variable (the headless/background id), and a derived `auto-<digest>` key (a short hash of the store path plus the intent id). The derived key is deterministic, so a session-less arm and a later session-less check resolve to the same session row rather than registering a null-session row. A null session can never be persisted.

The savepoint ledger is decoupled from this resolution. The `gate-check` hook derives the intent directory directly from the written file path (it walks up to the first ancestor that looks like `.../store/ID--slug`) and stamps the ledger event there before any session lookup. A missing session row, an unset session, or a headless background run no longer skips the ledger. Session resolution is strictly per-session (intent 90): it prefers an exact-session match, and when the caller has a session it resolves ONLY that session's own row(s). A foreign session's row is never returned, and a session that owns no row resolves to nothing, so its gates fail open rather than inheriting another session's armed intent. One carve-out (intent 168) runs before this per-session filter, and only for hook-code-gate, which passes the edited file path: when that path lies inside a provisioned code worktree (`<repo>/.claude/worktrees/{id}--{slug}`), resolution picks the session row whose worktree owns that directory, or no row at all when none owns it, so a session-keyed guided row can never claim a write located inside a sibling intent's worktree. This closes the cross-session freeze where a session with no bridge of its own inherited the newest armed bridge of any other live session (intents 49, 66). Only in the genuinely session-less headless case (the derived-key path, intent 52) does resolution widen to a cwd/auto-preference/recency tiebreak across that store's rows (`Plastic::DB::Sessions.active_for`). To keep the `sessions` table small, arming and disarming an auto run also end dead session rows, so the table does not accumulate over time (intents 67 and 80). The purge is terminal-state, not age-based: a row is removed only when its intent is no longer in its store's `INDEX.md` `## Active` block (and it holds no live delivery lease). An active intent's row is kept because it is still the continuation signal and the per-session anti-collision lock, and the current session's own row is never purged.

## worktree isolation and the delivery lock

An intent whose delivery touches code runs in its own git worktree, and an intent's delivery is single-owner: exactly one session develops it at a time. Both properties are owned by Plastic, not the harness (intents 73c, 108, and 41). The lock is a lease row in the store's `plastic.db` (`lock_leases` table), acquired atomically at arm time (check-then-insert inside one write transaction). It records the lock type (delivery grain, or a per-artifact claim), the owner session, the host, the acquired-at and expires-at times, and a delegates list; it never records a process id. Liveness is the lease's `expires_at`: renewal is coarse (only bumped once the remaining life is inside a window, never on every heartbeat), and the lock is stale once `expires_at` has passed (TTL 1800 seconds), fail-open by construction, so an expired lease never blocks. A fresh foreign lock means back off; a stale one is taken only by explicit takeover, which stamps an audit event to the intent's `savepoint_events` ledger. The bridge Hash's `lock` block is a cache of the lease row; when the two disagree, the lease row decides, so a lost `/tmp` (or a DB read that happens to race) never strands the owner. Repair is one idempotent function (`Bridge.repair_lock`) exposed by the `plastic-lock` CLI (status, fix, release, reclaim, delegate) and by the boarding skill. The bridge's `worktree` block records the code and store worktree paths and branches plus a `provisioned` flag.

## the operational database layer

Every store (global and each project) carries one disposable, git-ignored SQLite database, `plastic.db`, provisioned lazily on first real use and never committed (its WAL/SHM sidecars are git-ignored alongside it). One Ruby entry point, `Plastic::DB` (`scripts/lib/db.rb` plus the small `scripts/lib/db/` package under it), is the only surface any consumer touches; a thin `scripts/plastic-db` CLI mirrors the same verbs for shell callers (hooks, the statusline). No consumer writes SQL directly.

The schema splits into two families. **Operational tables** are authoritative: `sessions` (replaces the retired `/tmp` bridge), `lock_leases` (replaces the retired `delivery.lock` and `.claims/*.claim` files), `savepoint_events` (an append-only ledger, replacing the live-flow `savepoint.md` writes), and `roadmaps`/`roadmap_entries` (queue and batch membership). **Derived tables** are a rebuildable mirror: `intents` (frontmatter fields, reconciled by content hash whenever a read touches the store, debounced to once per few seconds) and `edges` (the `sources`/`chain` graph). Markdown stays the source of truth for stage (which lifecycle files exist) and for terminal disposition (`outcome.md`); the DB never restates those. On any conflict between a derived row and the files on disk, the files win.

Fail-open is load-bearing, not incidental: when the `sqlite3` gem is absent, or a store's DB file cannot be opened, every `Plastic::DB` call returns its documented fail-open value (an empty query result, or a sentinel for a write) and every gate that consults it falls back to ALLOW. Plastic runs correctly in markdown-only mode with no DB at all; the layer only adds speed and structure on top. `doctor` reports the gem's absence as advisory, never as a failure.

Because `savepoint_events` lives only in the DB, each delivery gate boundary (a lifecycle file landing, or the terminal `Done` event) additionally exports and git-commits `<intent_dir>/savepoint.jsonl`, a lossless line-per-event snapshot plus a trailing operational-state record (status, quadrant, queue, batch). That file is the durable recovery path: if a store's `plastic.db` is ever lost, `rebuild_savepoint` replays it back into the ledger, and a cold `Plastic::DB.rebuild!` reconstructs every derived table from the files and snapshots on disk, deterministically (a canonical, sorted, content-timestamped dump is byte-identical across two rebuilds of the same store).

Intent 41 replaced the lock/bridge/savepoint subsystem's **read-write** paths only. The gate-decision functions themselves (`code_gate_decision`, `worktree_gate_decision`, `lock_gate_decision`, `derive_stage`) are unchanged: `Plastic::DB::Sessions.to_bridge_data` adapts a session row into the same Hash shape the old bridge file produced, so those functions consume DB state through their existing interface. The **read** paths that parse `INDEX.md` directly for boarding, continuing, and the dashboard are a separate, later scope (intent 147); this layer does not touch them.

Provisioning is deterministic and cwd-independent. Plastic resolves the project repo from `projects.yml` and runs `git -C <repo> worktree add`, so it never relies on the current directory (this is the fix for the cwd-not-repo-root gap that silently degraded the harness worktree tool). Two worktrees are created per project intent, both named `{id}--{slug}`: a code worktree at `<repo>/.claude/worktrees/{id}--{slug}` on branch `plastic/{id}--{slug}`, where all code edits happen, and a store worktree at `<plastic_home>/.worktrees/{id}--{slug}` on branch `plastic-store/{id}--{slug}`, so lifecycle-doc commits travel in lockstep with code commits. Creation is idempotent: an existing worktree path is reused, not re-created. Disarming releases both worktrees (`git worktree remove` then `git worktree prune`) and clears the block.

Provisioning fails open: for a pure research or decision intent in the global store, or a repo that is not a git work tree, the code worktree is skipped, `provisioned` stays false, and the fall-back is logged to stderr (never silent). Such intents still get the lock.

The delivery lock arbitrates at the whole-intent grain only: two writers that both hold it, whether two delegates or two subagents sharing one session id, both pass this check on the same lifecycle file. Intent 111 adds a per-artifact claim underneath it: the same `lock_leases` table, one row per artifact (a non-NULL `artifact` column is the claim grain; NULL is the delivery grain), scoped strictly to that intent's own artifact, so a write must hold both the delivery lease and the specific file's claim lease. The claim gate is dormant unless a claim row exists, fails open on a stale claim (a lease row can never be "corrupt" the way a hand-parsed claim file could), and is visible in `plastic-lock status`. See `docs/internals.md` for the full mechanism.

The lock gate and the worktree gate are ARBITRATION: they exist to referee between competing sessions, not to enforce delivery order (that is the separate stage gate, `code_gate_decision`, untouched here). When there is nothing to arbitrate, a positively confirmed solo delivery, both gates run advisory instead of hard-denying (intent 128). `Bridge.solo_delivery?` scans the fresh delivery-grain `lock_leases` rows under the target intent's store plus the global store (never the retired `/tmp` bridge cache) and returns true only when exactly one fresh lease exists, it is owned by the current session, and its delegates array is empty. Any ambiguity, more than one fresh lease (including several under the same owner_session, which still reads as parallel), a foreign owner, a registered delegate, a blank session, or a scan error all keep today's fail-closed denies verbatim. On a confirmed solo, `lock_gate_decision`'s no-lease, stale, and fresh-foreign-lease denies, and `worktree_gate_decision`'s two rules (worktree confinement and non-owner store edits), return an advisory allow (with one terse stderr line) instead of a hard deny. The stage-ordering gate and the per-artifact claim gate are never relaxed by this.

### intent done and the end tail (intent 93)

Done is one law with three signals that must agree. The INDEX `## Completed` or `## Abandoned` section is the single canonical terminal marker (the store-wide ledger a fresh session reads first), so it wins on any conflict. `outcome.md` is the deliverable-exists signal, mandatory at every terminal (delivered and abandoned alike) and self-declaring through a `disposition: delivered|abandoned` frontmatter header. The savepoint `Done delivered|abandoned` line is the audit echo. When the three disagree, INDEX is authoritative and `doctor` (the `done_signals` check) reports the mismatch.

The End tail runs in a fixed order, and the QMD reindex is always last, after the purge: `outcome.md`, then the INDEX terminal move, then the savepoint `Done` event (stamped to `savepoint_events` and exported to the committed `savepoint.jsonl`), then the commit, then disarm (worktree release, then the delivery lease release, then the session-row purge), and finally the QMD reindex. Running the reindex after disarm keeps the search index from referencing a session or lease that is about to disappear. The post-done access window is bounded by the delivery lease, `[INDEX terminal to lease release]`: while the lease is held the completing session keeps full access and no purge fires, and once the lease is released the session row is purged and the directory is frozen (writable again only under the future maintenance lock, the contract intent 112 enforces).

## dashboard

The dashboard is the work cockpit. It answers three questions: where we are (recently worked), where we go next (a Value by Effort matrix), and how to conduct each item (a disposition). The split keeps determinism while reaching a Markdown UI:

- **Heavy script, mechanical fill**: `dashboard.rb --data [continue|project <slug>]` emits one complete JSON payload (recently worked, the full matrix with per line glyphs, counts, project summaries). The `plastic-dashboard` skill fills a Markdown template from that payload with near zero reasoning and presents the filled board in its reply. Same store state gives the same payload regardless of model.
- **Markdown surface**: the board is Markdown because the user's UI renders Markdown natively but collapses raw tool-call stdout. Templates live in the skill's `templates/` directory (`dashboard-global.md`, `dashboard-project.md`). The matrix is a small table holding only the quadrant signature and count, with each quadrant's intents printed below it as glyph led lines (the glyph is the bullet, never a Markdown dash, never an HTML break).
- **Entry flow**: the global board lists recently worked across all scopes, a matrix of global intents only, and a summary of the last five projects (counts plus last accessed). The board is the menu: the user replies in free prose with an intent id, a project name (which re-runs the script for that project), or a request to start something new. No capped multiple choice picker.
- **Heuristics**: value is high for an explicit `value: high` field, a human authored root, or an intent that is a source of another (it has spawned follow-on work). A purely relational chain entry alone is not a value signal (intent 68). The `unblocked` flag fires only when a future intent has all of its sources done AND at least one source's completion date is strictly later than the intent's own created date (a genuine wait, not a birth-time default); `in-progress` requires real post-birth savepoint activity, not just the creation stamp; `stale` only on aging future intents, so flags stay low noise.
- **Caps**: the Markdown board's quadrant lists and the project board's active/future lists are capped at 8 entries plus a "+N more" line, and each entry's text is truncated to 120 characters with a trailing ellipsis, so a large store cannot print an unbounded dump.
- **Auto-mode contract**: `--json` still emits the machine readable manifest (`dispatchable_queue`, `human_only`, `next_big_thing`) that `plastic-auto` consumes. The plain text modes remain for a raw terminal.
