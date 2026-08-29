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
- **How**: the work is planned (`plan.md` plus `checklist.md` plus at least one real `actions/ACTION_N.md`).
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
  actions/        # real action files, at least one per planned intent (one consolidated file at S/M, one per task at L)
  resources/      # research, references, snapshots, diagrams
```

Lifecycle artifacts use those exact reserved names and live directly in the intent folder, never in subfolders and never renamed. All other supporting material goes in `resources/`. State is not stored in a status field; it is derived from which files and sections exist (for example, an empty `## Context` means the intent is still fleeting, and the presence of `outcome.md` means it is done). `revisions.md` is not a lifecycle artifact: it appears only when structural maintenance relocated a misplaced section, file, or ref out of a delivered intent, so its existence signals structural (not conceptual) change.

### the session day ledger

Alongside a store's intent directories, the global store carries two dot-prefixed paths (intent 297): `.sessions/`, one shared day ledger per calendar date, and `.tmp/`, a per-session scratch area. Both are invisible to every store walker precisely because of the leading dot, so neither one is, or ever becomes, an intent:

```
~/.plastic/
  INDEX.md
  config.yml
  projects.yml
  store/
    ID--slug/
    .sessions/
      YYYYMMDD/
    .tmp/
      <session-id>/
```

A day directory's members appear in order as the day is used, not all at once:

```
.sessions/YYYYMMDD/
  YYYYMMDD.md    # the only file at scaffold time
  checklist.md   # on the first append, header written under the lock
  savepoint.md   # on the first append, no header
```

The day id is the local wall-clock date, digits only with no hyphen, so it satisfies every id pattern in the store with no special case. One day directory is shared by every session that touches that day, project agnostic, with each checklist and savepoint line tagged by session and project. A day ledger has no `INDEX.md` entry. `scripts/append-ledger` is the only writer of `checklist.md` and `savepoint.md` inside a day directory.

### the session branch model and session-commit

A verified checklist item becomes one commit through `scripts/session-commit` (intent 300), which resolves the repository containing `--cwd`, loads that repository's `flow:` setting from its `project.yml`, and applies the branch model: under `mode: direct` (the default) it commits to a session branch cut from the repository's own base branch and fast-forwards the base into that commit; under `mode: pull_request` it cuts a small branch and PR per item instead. The five flow knobs (`mode`, `base`, `branch_template`, `ticket_source`, `workspace`) are documented in `templates/project.yml` and validated by `scripts/lib/project_validator.rb`. `session-commit` is fail-open throughout: no repository, a detached HEAD, a clean tree, an agent-owned branch, a refused push, a missing `gh`, or a rejected commit-msg hook all degrade to no commit plus one `Note` savepoint line, never a non-zero exit. Every outcome writes exactly one `Item` or `Note` line to the day's `savepoint.md` through `SessionLedger`. See [internals](internals.md#the-session-branch-model-and-session-commit-intent-300) for the mechanics.

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

- **Skills**: the workflows agents follow (routing a prompt in direct mode via `plastic-direct`, creating intents, brainstorming, writing plans, executing, releasing, indexing, and authoring skills, agents, and hooks via `plastic-skill-creating`). They produce the lifecycle artifacts in their fixed forms.
- **Agents**: role files shipped in `agents/` that the installer syncs into each harness agent directory (Claude, codex, hermes) and tracks in that harness's manifest, so they prune on update and uninstall cleanly. In auto mode they form a 5-role enforcer-led team (one team per intent): brainstorming, spec-specialist, planner, executor, and a plastic-enforcer that orchestrates the others and owns every gate. See `skills/auto/references/agent-architecture.md` for the team model.
- **Hooks**: lifecycle event handlers. A SessionStart hook detects the active project by matching the working directory; transition gates are enforced by hooks that block (non-zero exit) when a stage's preconditions are not met on the filesystem. Claude's five PreToolUse edit-path gates (code-gate, lock-gate, savepoint-pre, links-gate, and create-gate) register as ONE hook, `hooks/edit-gates` -> `scripts/hook-edit-gates` (intent 244): it parses the payload once and runs all five checks in-process, in a fixed order, with the first deny ending evaluation. The create gate among them (matcher Write plus Edit plus the Serena MCP edit tools, intents 60b and 108) blocks a mutation of an intent file that is not born complete or structurally sanctioned: a Write is judged on its proposed content, an Edit on the simulated replacement result, and a pathless MCP edit on the current on-disk file, all independent of any session bridge. Hook registration itself has one source of truth, `scripts/lib/hook_registry.rb`: the installer merge and the plugin `hooks/hooks.json` derive from it, per-gate applicability lives in `HookRegistry::GATE_TOOLS`, and doctor's `hooks_match_registry`, `claude_hooks_implemented_check`, `hooks_entries_owned`, and `codex_hooks_entries_owned` checks flag drift. Deterministic by construction.
- **Scripts**: small deterministic Ruby programs that encode mechanical rules, for example assigning the next Folgezettel ID from the existing IDs in a store. Intent creation has a one-call contract here: `scripts/new-intent` allocates the id, creates the directory tree, renders the born-complete intent file, writes the sentinel placeholder lifecycle files, wires the reciprocal links, and self-validates, so the sanctioned path is one CLI call rather than several hand-authored writes (intent 60b). It does not touch INDEX.md, git, or project creation; those stay in the creating-intent skill. `scripts/lib/feedback_report.rb` plus the thin `scripts/feedback-report` CLI (intent 174) back the user-only `plastic-feedback` skill: they redact secrets, write a local report file, and build a prefilled GitHub issue URL, with no send path anywhere in the code. Four scripts wrap the deterministic steps of intent delivery: `scripts/start-intent` arms the lock and prints the resume station, `scripts/scaffold-intent` writes the mechanically derivable parts of spec.md, checklist.md, and outcome.md, `scripts/verify-intent` folds doctor, an added-line em-dash diff guard, a diffstat, and an optional caller-supplied suite command into one verdict, and `scripts/exec-worktree` wraps `Worktree.finish` behind a friendly order precondition. Deterministic by construction.
- **Templates**: the fixed FORM of each artifact (its sections, their order, frontmatter fields, file name). Two people following the same template produce artifacts of identical shape even when the words differ. Deterministic by construction.
- **Evals**: checks that verify skills produce convention-compliant output and that descriptions trigger correctly.
- **Conventions**: Plastic's own doctrine ships in three tiers (intent 223), not one file. `PLASTIC.md` (installed at `~/.plastic/PLASTIC.md`) is the always-on core, injected at every session start, held under 500 lines and 5,000 estimated tokens by a dedicated Minitest test (`test/plastic_core_budget_test.rb`), the regrowth-enforcement mechanism after two prior splits each shrank it once with nothing holding the boundary. `skills/conventions/` (installed as `plastic-conventions`, `user-invocable: false`) is a thin router skill covered by skill-lint's five checks like any other skill. Doctrine used by more than one skill lives in its 8 `references/*.md` chapters, each reached only by a consuming skill's own bound load line; an unbound chapter, or a load line pointing at a chapter that does not exist, is caught by the same test. `skill-lint`'s own scope stays `skills/*/SKILL.md`; it does not read `PLASTIC.md`.

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

Every agent in `agents/*.md` pins an explicit Claude Code model alias (`opus` or `sonnet`) in its frontmatter: never `inherit`, never Fable by default, unless an explicit `agents.models.<name>` config override names Fable for that role, in which case the override is honored as written. The two advisors, `plastic-advisor` and `plastic-faux-advisor`, are not lifecycle stage roles: the never-Fable rule governs stage agents only. Neither is ever dispatched by the auto pipeline; they are consultation roles summoned deliberately by the user or the main session, and their models are user configuration (fable and opus by default on Claude Code). The tier is by role weight, not by stage:

| Agent | Model |
|---|---|
| `plastic-enforcer`, `plastic-brainstorming`, `plastic-planner` | `opus` |
| `plastic-spec-specialist`, `plastic-executor`, `plastic-intent-curator`, `plastic-future-intent-researcher`, `plastic-intent-discovery` | `sonnet` |

A project or the global store can override any agent's tier through `agents.models.<basename>` config; see [internals](internals.md) for the config precedence and the installer mechanism that applies it. Every dispatch site also resolves and passes the target agent's model explicitly at dispatch time, belt-and-braces on top of the frontmatter pin, since reading frontmatter at dispatch is a harness detail rather than a Plastic-owned contract. At auto-mode start, the orchestrator advises (never gates) that the user run the main session on the best available thinking model for the sharpest synthesis; this is the one context where Fable is named as an acceptable choice, since it concerns the human's session, not a subagent.

### the advisor: two consultation agents, never injected (intent 185)

Two Claude-only role files, tracked separately from the lifecycle tiers by `AgentModels::CONSULTATION_AGENTS` (excluded from `TIER_DEFAULTS`, so neither carries a built-in Codex reasoning-effort mapping, and neither is ever dispatched by the auto pipeline). `plastic-advisor` is the real advisor, shipped frontmatter `model: fable`. `plastic-faux-advisor` is the imitation advisor, shipped frontmatter `model: opus`, with the full Operating Manual text inlined in its own body (not injected into anything: inlining is what makes an ordinary model reason at frontier level, and it must not depend on the agent choosing to read a file). Neither name claims a specific vendor identity beyond "the advisor, whatever model is running you today." Each agent's actual model resolves through the SAME harness-scoped `agents.models.claude.<name>` mechanism every other agent uses (`InstallerCore#agent_model_overrides(harness:)`); there is no separate advisor-model config key, so an override for `plastic-advisor` or `plastic-faux-advisor` is a plain per-agent override like any other.

The `plastic-agent-advisor` skill (`skills/agent-advisor/`) is the one front door. It teaches when consulting is worth the money (from the shipped Advisor Protocol: buy one-way doors, plans, adversarial review, deadlocks, ranking; never buy what a tool can answer, code volume, or confirmation of a decision already made), reads the harness-scoped config to route to the configured agent (`advisor.claude.default`, falling back to `advisor.claude.secondary`, then to `plastic-faux-advisor`), and can set the config on request. The shipped Advisor Protocol lives in the skill's `references/advisor-protocol.md`, derived from the owner's original document. The user or the main session states a TIER (S, M, or L) and an EFFORT line in the brief; shipped effort is `xhigh` for `plastic-advisor` (expensive, so raised by default) and `max` for `plastic-faux-advisor`.

Config, harness-scoped with keys matching `InstallerCore::DEFAULT_AGENTS` exactly (`claude`, `codex`, never `claude_code`): `advisor.enabled` (false skips installing both advisor agents AND the `agent-advisor` skill, on every installed harness); `advisor.claude.default` / `.primary` / `.secondary` (agent NAMES, never model names, so a slot can point at a locally registered agent; resolution never maps a nickname). Install (Claude Code only) asks whether the user wants the advisor at all, and if so which is the default, with a plain description of each (Faux Fable, recommended, cheaper; or Fable 5, the frontier model, billed through credits); non-interactive installs default to the faux advisor by leaving the key unset, which the skill's own routing resolves to `plastic-faux-advisor`. Update asks the same question once when the key is unset after an update that ships this, then never again. Installer flags: `--no-advisor` and `--advisor VALUE` (an agent name, or the shorthand `real`/`faux`).

`agents.models` is harness-scoped from this release: `agents.models.claude.*` and `agents.models.codex.*`, with the pre-existing flat form (`agents.models.<name>: value`, no harness nesting) still honored as the claude harness, and nested winning over flat for the same agent. `AgentModels.models_section(config, harness:)` implements this: for `harness: "claude"` it merges the flat scalar entries with the `claude` sub-hash (nested wins); for any other harness it reads ONLY that harness's own nested sub-hash, never the flat entries. This closes a real latent bug: previously the same override map fed both `install_agents`' Claude frontmatter rewrite and `generate_codex_agents`' TOML `model` line, so a literal Claude model id set under the flat form could leak straight into a Codex config. `install_codex` now calls `agent_model_overrides(harness: "codex")`, so a model named under `claude` is never emitted to `codex`; a regression test (`test_agent_model_overrides_never_leaks_a_claude_model_id_into_codex`) pins this. Stage-agent tier translation to Codex reasoning effort (`AgentModels::EFFORT_BY_ALIAS`) is unchanged by this scoping.

`InstallerCore#generate_codex_agents` skips every `AgentModels::CONSULTATION_AGENTS` file by name before rendering any TOML: no Codex advisor ships in this release, a deliberate, mechanical scope cut (the owner has not evaluated the Codex reasoning-model ecosystem long enough to judge it), tracked at intent 186, not a permanent exclusion. An `agents.models.<name>` override that flips a non-consultation agent's authored model to `fable` is still honored as written (intent 170) and is unaffected by this name-based skip.

Codex per-role model identity (intent 186): Codex has no vendor alias layer, so `AgentModels::CODEX_MODEL_BY_ALIAS` centralizes every Codex model id in one place, paired with the existing `AgentModels::EFFORT_BY_ALIAS` tier. A generated Codex agent TOML for a tier alias carries both lines, model first:

| Tier | Codex model | Reasoning effort |
|---|---|---|
| `opus` roles | `gpt-5.6-sol` | `high` |
| `sonnet` roles | `gpt-5.6-terra` | `medium` |
| `haiku` roles | `gpt-5.6-luna` | `low` |

Both are shipped defaults, overridable per role through `agents.models.codex.<name>` (a tier word selects model and effort together; a literal Codex model id wins verbatim, `model` only, no effort line). The advisor Codex pairing is decided (`plastic-advisor` to `gpt-5.6-sol` at `xhigh`, `plastic-faux-advisor` to `gpt-5.6-terra` at `high`) but emission stays deferred: `generate_codex_agents` still skips both `AgentModels::CONSULTATION_AGENTS` files.

### qmd search integration

QMD is an optional, recommended local markdown search engine layered over the stores. Plastic functions without it (ripgrep over the store files is the fallback), so the integration adds search without becoming a dependency. The topology is one collection per store in the default qmd index, all `plastic-` prefixed: `plastic-global` for the global store and `plastic-<slug>` for each project store (slugs from `projects.yml`). Plastic delegates all index mechanics to the qmd CLI through a single helper (`scripts/lib/qmd_sync.rb`, exposed as the `scripts/qmd-sync` CLI, with verbs for detect, register, reindex, status, and a read-only `search`) and never reimplements qmd commands. Index mutation is tied to lifecycle events only, never ad-hoc: install registers all stores, project creation registers the new project store, and intent delivery reindexes the delivering store's collection. That delivery reindex is mandatory on completion and runs async (detached, non-blocking) so it never holds up the turn. Session start is report-only and never mutates the index. Query craft itself is owned by the installed `qmd` skill, not by Plastic.

A power-tools hook on `UserPromptSubmit` keeps the search layer visible instead of relying on agent memory. It appends one recommendation line covering whichever tools are present: "QMD is available: prefer `qmd search` / `qmd query`" when only qmd is present, "Serena is available: prefer its symbolic tools" when only Serena is present, and ONE combined line naming both when qmd and a code-navigation tool are both present (never one line per tool). The code-navigation slot names only Enola (not both) whenever Enola is also present (Enola-first, one code-navigation slot, per the owner's Enola-first ruling; Enola presence is checked the same way as Serena, an `.enola` marker directory or `enola` on PATH). These are recommendations, not obligations (intent 108, D8); reads and searches are never gated. Tool presence is computed by a small power-tools harness (`scripts/lib/power_tools.rb`: `PowerTools.qmd?`, `PowerTools.serena?`, `PowerTools.mandate`), where Serena is detected by a `.serena` marker in the working directory or an ancestor, or `serena` on PATH. All three probes are PATH and marker-file walks with no subprocess. It is a silent no-op when no tool is present, bounded by a short timeout. The decision logic lives in `scripts/lib/qmd_hook.rb` (pure, dependency-injected). The hook itself does not search: intent 225 measured per-prompt hit injection at 0.24 intent-level recall@3 against a plain ripgrep control at 0.18, while agent-driven `qmd query` scored 0.71, so intent 246 removed the injection and kept the recommendation. `QmdSync.search` is untouched and still backs the `scripts/qmd-sync search` CLI verb. The per-skill QMD-first steps reinforce the same discipline: search qmd first, then open the authoritative intent file, with a no-op fallback when qmd is absent.

### intent born-complete validation

A single validator library, `scripts/lib/intent_validator.rb`, defines whether an intent is born complete (every required frontmatter field present, and `sources` and `chain` well-formed arrays of id references (bare ids, or cross-store references like global:1a2)). It is the only definition of that contract. It is exposed as the `scripts/validate-intent` CLI (exit 0 when complete, non-zero with a report otherwise) and consulted by both the `plastic-intent-creating` skill (a self-verify step after the write) and doctor (the `frontmatter_fields` and `frontmatter_valid` conventions checks). Intents are created only through `plastic-intent-creating` and never hand-authored, so completeness rests on machinery rather than on agent discipline.

### project store provisioning

Project store creation has a single source of truth: the `scripts/provision-project-store` verb, backed by `scripts/lib/store_provisioning.rb`. It is pure filesystem and idempotent: it makes the store directory at `~/.plastic/projects/{slug}/store`, then writes, only if missing, `.gitkeep`, `INDEX.md` (from `templates/index.md`), and `project.yml` (from `templates/project.yml`). It requires the project to already be registered in `projects.yml` (an unregistered slug exits non-zero and creates nothing) and performs no qmd mutation, so any caller (including a doctor fix) stays deterministic. The `plastic-intent-creating` and `plastic-project-creating` skills call it instead of an inline `mkdir`, and `plastic-store-provisioning` adds a store to an already-registered project and then runs the separate optional `qmd-sync register` step. Doctor's additive `project_store_dir` check warns (fixable) when a registered project's store directory is missing, naming `provision-project-store {slug}` as the fix.

## session boot

Boot is owned by hooks, so it runs by construction on every session start, not as prose a skill follows (intent 36a):

1. **Core doctor**: `hook-session-start` runs `doctor.rb --core` in-process, reusing the `Doctor` class so there is one source of truth for core health. The core check is binary (pass or error, never warn): it compares every core file against the SHA256 recorded in the install manifests (`~/.plastic/manifest.json` for global scripts and PLASTIC.md; `~/.claude/plastic/manifest.json` for agent-side files), and also confirms hooks are registered, scripts are executable, and the installed version matches.
2. **Load core**: the same hook injects only the core conventions (`PLASTIC.md`); deeper doctrine is loaded on demand, by whichever skill runs, from that skill's own bound `plastic-conventions` chapter, not primed at boot. The hook also reads the store INDEX.md and projects.yml, detects the current project by matching the working directory, and loads that project's state.
3. **Boot banner and version**: the result of the core check drives a binary banner. On pass: `Plastic Core loaded - v{version} | doctor --core run: success`. On error: `Plastic Core loaded - v{version} | doctor --core run: error - run /plastic-doctor`. The banner is emitted on both the `hookSpecificOutput.additionalContext` channel (model-facing) and the top-level `systemMessage` channel (visible in the user's terminal). One `BootBanner` renderer feeds both channels so they cannot drift (intent 54). The hook never blocks (always exits 0).
4. **Statusline**: the always-on `plastic-statusline` StatusLine hook sets the statusline (a distinct hook event that cannot be set from SessionStart). This is the render-time behavior once Plastic's statusline is configured; whether it gets configured at all is an install-time decision (see below).

Install-time statusline choice is separate from the render-time hook above: `InstallerCore#statusline_choice` decides, once per install, whether to write Plastic's statusline over an existing one. A fresh settings file with no statusline gets Plastic's line with no prompt. An existing non-Plastic line triggers a keep-or-switch prompt in an interactive session, honors `--statusline keep|plastic` to skip the prompt, defaults to keeping the user's line in a non-interactive session, and is never re-asked on `--reinstall` (a repair keeps whatever is already configured). `merge_claude_hooks` still backs up the prior line to `~/.plastic/.cache/original-statusline.json` regardless of the choice, so a later switch or an uninstall can restore it.

The `plastic-continuing` skill is the front door that then continues work: it is a thin router, deciding among three routes and dispatching to exactly one. The project route (`plastic-project-continuing`) is the default for a bare "continue": it lands on the board (the project board when a project is loaded, otherwise the global board, invoking the renderer rather than rendering itself), presents choices, and stops. The intent route (`plastic-intent-continuing`) fires when a specific intent is named to resume: it reads that intent's `savepoint.md` ledger FIRST (intent 81) and hands off to `plastic-intent-starting`, which takes the lock and runs the cycle from there. The roadmap route (`plastic-roadmap-continuing`) resumes a mid-flight roadmap by calling `scripts/roadmap-next` (intent 148), which liveness-ranks the tier's roadmap files and selects the frontier batch deterministically, rather than ranking by eye. None of the three routes run the health check, load core, or set the statusline, all of which the hooks already did, and none drive work autonomously on their own (that is `plastic-auto`, reached only through `plastic-intent-starting`'s or `plastic-roadmap-continuing`'s auto branch). On the intent route, the last ledger line classifies the state (a cycle position, or `Done delivered|abandoned` for a terminal intent), and it verifies only that last line's artifact before continuing, rebuilding the ledger from files on drift. The ledger's fixed bookends, a born `What created` first line and a `Done` last line, make state a single read instead of a filesystem probe.

### direct mode

A booted session rests in direct mode, where the prompt itself is the action and the work runs inline rather than through a dispatched agent. The `plastic-direct` skill routes each prompt in a single read, on a time estimate made from the prompt alone: a bounded change of about five minutes or less runs now, a prompt that one answer would settle gets one clarifying question and then runs, anything that stays vague is offered a thinking intent (`plastic-intent-speccing`) rather than guessed at, and a bounded change over the budget is offered a dedicated intent. An explicit "auto" hands off to `plastic-auto`. The skill itself ships no wiring: intent 298 owns the capture hook, the session-start mode line, and the per-session day-ledger pointer, and intent 305 owns the `PLASTIC.md` core block that states every session starts in direct mode. Until both land, `plastic-direct` is installed but nothing steers prompts to it.

Each roadmap carries the same kind of ledger for the same reason (intent 134): a name-paired `roadmaps/<slug>.savepoint.md`, the machine counterpart to the human `## Log`, following its roadmap into `roadmaps/archived/` on close. The `plastic-roadmap` skill's verbs append to it at the same closing-step slot each already uses for its QMD reindex (created, dispatched, parked, merged, release, handoff, closed), and `plastic-roadmap-continuing` reads its last line as a cheap last-event signal on resume. Like the intent-dir ledger, it is derived and rebuildable from source, never a status source: `INDEX.md` stays the single writer of intent status.

## the session bridge and the gate hooks

The gate hooks share a session bridge: a small JSON file under `/tmp` that records the active intent and whether auto mode is armed. Resolving which bridge to use has a fixed precedence (intent 52). Claude Code does not export a session id env var into the hook environment; it passes `session_id` on the hook stdin JSON. So the bash wrappers parse `session_id` out of stdin (in Ruby, never in bash) and pass it to the gate scripts. The resolver then picks the first non-empty of: the stdin `session_id`, the `CLAUDE_CODE_SESSION_ID` environment variable (the headless/background id), and a derived `auto-<digest>` key (a short hash of the store path plus the intent id). The derived key is deterministic, so a session-less arm and a later session-less check land on the same bridge file rather than writing a null-session bridge. A null session can never be persisted.

The savepoint ledger is decoupled from this resolution. The `gate-check` hook derives the intent directory directly from the written file path (it walks up to the first ancestor that looks like `.../store/ID--slug`) and appends the savepoint there before any bridge lookup. A missing bridge, an unset session, or a headless background run no longer skips the ledger. Bridge discovery is strictly per-session (intent 90): it prefers an exact-session match, and when the caller has a session it resolves ONLY that session's own bridge. A foreign session's bridge is never returned, and a session that owns no bridge resolves to nothing, so its gates fail open rather than inheriting another session's armed intent. One carve-out (intent 168) runs before this per-session filter, and only for hook-code-gate, which passes the edited file path: when that path lies inside a provisioned code worktree (`<repo>/.claude/worktrees/{id}--{slug}`), discovery resolves the candidate whose worktree owns that directory, or no bridge at all when none owns it, so a session-keyed guided bridge can never claim a write located inside a sibling intent's worktree. This closes the cross-session freeze where a session with no bridge of its own inherited the newest armed bridge of any other live session (intents 49, 66). Only in the genuinely session-less headless case (the derived-key path, intent 52) does it fall back to scanning the `/tmp` bridges: keeping only valid ones, preferring auto-armed bridges, then those whose store matches the working directory, breaking ties by newest file. To keep that scan cheap, arming and disarming an auto run also purge dead bridge files, so the `/tmp` directory does not accumulate over time (intents 67 and 80). The purge is terminal-state, not age-based: a bridge is removed only when its intent is no longer in its store's `INDEX.md` `## Active` block (or the bridge is unparseable or store-less junk). An active intent's bridge is kept because it is still the continuation signal and the per-session anti-collision lock, and the current session's own bridge is never purged.

## worktree isolation and the delivery lock

An intent whose delivery touches code runs in its own git worktree, and an intent's delivery is single-owner: exactly one session develops it at a time. Both properties are owned by Plastic, not the harness (intents 73c and 108). The lock is a durable `delivery.lock` JSON file inside the intent directory, acquired atomically (O_EXCL) at arm time. Its `owner_session` is the sole authorization identity. Controller provenance (`harness`, `agent`, `model`, `thread`, and `mode`) is descriptive only, accepts explicit values from the harness, and is never inferred from transcripts or paths; legacy omissions render as `Unknown`. Liveness is a lease: write-path hooks refresh the file mtime on owner activity, and that mtime is the sole heartbeat and freshness truth against the 1800-second TTL. A fresh foreign lock means back off; a stale one is taken only by explicit takeover, which appends an audit line to savepoint.md and replaces the prior controller. Rearming the same session refreshes known provenance without changing authority. The bridge's `lock` block is a cache of the file; when the two disagree, or the bridge is missing entirely, the lock file decides, so a wiped `/tmp` never strands the owner. Repair is one idempotent function (`Bridge.repair_lock`) exposed by the `plastic-lock` CLI (`who`, status, fix, release, reclaim, delegate) and by the boarding skill; it also migrates legacy bridges whose lock block still carries a pid. `who` is a read-only durable-files view of controller, mtime heartbeat, delegates, and claims. The bridge's `worktree` block records the code worktree path and branch plus a `provisioned` flag.

Provisioning is deterministic and cwd-independent. Plastic resolves the project repo from `projects.yml` and runs `git -C <repo> worktree add`, so it never relies on the current directory (this is the fix for the cwd-not-repo-root gap that silently degraded the harness worktree tool). One worktree is created per project intent, named `{id}--{slug}`: the code worktree at `<repo>/.claude/worktrees/{id}--{slug}` on branch `plastic/{id}--{slug}`, where all code edits happen. A second, store worktree used to exist; intent 178 retired it, and store-write safety for lifecycle-doc commits now comes from intent 197's branch-from-main plus scoped-commit mechanism. Creation is idempotent: an existing worktree path is reused, not re-created. Disarming releases the worktree (`git worktree remove` then `git worktree prune`) and clears the block.

Provisioning fails open: for a pure research or decision intent in the global store, or a repo that is not a git work tree, the code worktree is skipped, `provisioned` stays false, and the fall-back is logged to stderr (never silent). Such intents still get the lock.

The delivery lock arbitrates at the whole-intent grain only: two writers that both hold it, whether two delegates or two subagents sharing one session id, both pass this check on the same lifecycle file. Intent 111 adds a per-artifact claim token underneath it (`.claims/<artifact>.claim`, one small JSON file per artifact, scoped strictly to that intent's own artifact) so a write must hold both the delivery lock and the specific file's claim. The claim gate is dormant unless a claim file exists, fails open on a stale or corrupt claim, and is visible in `plastic-lock status`. See `docs/internals.md` for the full mechanism.

Controller, delegate, and claim records answer different questions. The controller owns the intent, a registered delegate is a separately authorized child session, and a claim identifies the current writer for one artifact. Delegate activity status (`active`, `finished`, or `failed`) is descriptive and does not remove the session from the string-array authorization list. A delegate remains authorized until a separate removal mechanism exists. Finished and failed activity history is bounded to the 20 most recent terminal entries.

The lock gate and the worktree gate are ARBITRATION: they exist to referee between competing sessions, not to enforce delivery order (that is the separate stage gate, `code_gate_decision`, untouched here). When there is nothing to arbitrate, a positively confirmed solo delivery, both gates run advisory instead of hard-denying (intent 128). `Bridge.solo_delivery?` scans the durable `delivery.lock` files under the target intent's store plus the global store (never the `/tmp` bridge cache) and returns true only when exactly one fresh lock exists, it is owned by the current session, and its delegates array is empty. Any ambiguity, more than one fresh lock (including several under the same owner_session, which still reads as parallel), a foreign owner, a registered delegate, a blank session, or a scan error all keep today's fail-closed denies verbatim. On a confirmed solo, `lock_gate_decision`'s no-lock, stale, corrupt, and fresh-foreign-lock denies, and `worktree_gate_decision`'s two rules (worktree confinement and non-owner store edits), return an advisory allow (with one terse stderr line) instead of a hard deny. The stage-ordering gate and the per-artifact claim gate are never relaxed by this.

### intent done and the end tail (intent 93)

Done is one law with three signals that must agree. The INDEX `## Completed` or `## Abandoned` section is the single canonical terminal marker (the store-wide ledger a fresh session reads first), so it wins on any conflict. `outcome.md` is the deliverable-exists signal, mandatory at every terminal (delivered and abandoned alike) and self-declaring through a `disposition: delivered|abandoned` frontmatter header. The savepoint `Done delivered|abandoned` line is the audit echo. When the three disagree, INDEX is authoritative and `doctor` (the `done_signals` check) reports the mismatch.

The audit echo can itself drift, so a pure, disk-only detector (`Bridge.savepoint_phantom_lines`, intent 134) checks it: a savepoint line is a phantom when its file-landing milestone is absent or still a sentinel placeholder, its `(stage, milestone)` pair is a duplicate, or a state line's stage prerequisite is missing on disk. A live (INDEX Active) intent auto-rebuilds through `plastic-intent-savepoint`; a terminal (Completed/Abandoned) intent is immutable, so a phantom there is report-only, surfaced as a `doctor` `check_done_signals` advisory that warns, never fails.

The End tail runs in a fixed order, and the QMD reindex is always last, after the purge: `outcome.md`, then the INDEX terminal move, then the savepoint `Done` line, then the commit, then disarm (worktree release, then `Lock.release`, then the bridge purge), and finally the QMD reindex. Running the reindex after disarm keeps the search index from referencing a bridge or lock that is about to disappear. The post-done access window is bounded by the delivery lock, `[INDEX terminal to Lock.release]`: while the lock is held the completing session keeps full access and no purge fires, and once the lock is released the bridge is purged and the directory is frozen (writable again only on an explicit owner grant; there is no maintenance lock, the one intent 112 proposed was abandoned).

Since intent 188, `scripts/end-intent` performs disarm itself, as its own step 5 after the
outcome/INDEX/savepoint/commit steps commit: the script's exit code 0 now means both "the
intent is closed" and "its delivery lock is gone," rather than the second half being left to
a separate one-liner an agent had to remember to run. A pre-flight guard resolves the calling
session and refuses the whole run before anything is written when a live foreign session
holds the lock, and reclaims a stale foreign lock automatically (audited to savepoint.md). A
dirty code worktree refuses before removal (rather than the existing force-remove path
silently discarding uncommitted changes), unless an explicit `--discard-worktree-changes`
flag overrides it. `end-intent`'s own INDEX-move parser and `Bridge.intent_active?` now share
one matcher that accepts a real em dash or a plain hyphen as the id/title separator on read,
while every write still emits the real em dash.

## dashboard

The dashboard is the work cockpit. It answers three questions: where we are (a short prose summary of recent delivery, plus capped active work), where we go next (the most-valuable next work, ranked), and how to conduct each item (a disposition). The split keeps determinism while reaching a Markdown UI:

- **Heavy script, mechanical fill**: `dashboard.rb --data [continue|project <slug>]` emits one complete JSON payload (a prose summary, the capped active list, the ranked next-work list, counts, project summaries, an honest-totals footer). The `plastic-dashboard` skill fills a Markdown template from that payload with near zero reasoning and presents the filled board in its reply. Same store state gives the same payload regardless of model.
- **Markdown surface, short by default (intent 202)**: the board is Markdown because the user's UI renders Markdown natively but collapses raw tool-call stdout. Templates live in the skill's `templates/` directory (`dashboard-global.md`, `dashboard-project.md`). The project board shows, and shows only, a 2-3 sentence prose summary of what was delivered most recently, an Active table capped at 3 (ordered lifecycle-stage descending, a later savepoint breaking a tie within a stage), a Next-work table capped at 5, and a one-line footer stating true totals. The global board gets the same treatment: the prose summary replaces its recently-worked table, and the same honest-totals footer sits beside its next-work table. The raw Future table (which duplicated Next-work, ranked) is gone from the project board, and the recently-worked table is gone from both.
- **Entry flow**: the board is the menu: the user replies in free prose with an intent id, a project name (which re-runs the script for that project), or a request to start something new. No capped multiple choice picker.
- **Worker visibility**: active intent rows derive Worker and Activity from the same durable lock view as `plastic-lock who`. They show explicit controller harness and agent values, freshness from the lock file mtime, and `Unknown` for absent legacy provenance. The dashboard never searches harness transcripts or guesses from session-id shape.
- **Heuristics**: value is high for an explicit `value: high` field, a human authored root, or an intent that is a source of another (it has spawned follow-on work). A purely relational chain entry alone is not a value signal (intent 68). The `unblocked` flag fires only when a future intent has all of its sources done AND at least one source's completion date is strictly later than the intent's own created date (a genuine wait, not a birth-time default); `in-progress` requires real post-birth savepoint activity, not just the creation stamp; `stale` only on aging future intents, so flags stay low noise.
- **Caps, explicit and honest (intent 202)**: the Active cap (3) and Next-work cap (5) are `dashboard.rb` defaults, overridable per section with `--limit-active`/`--limit-next`, or lifted entirely with `--all`; each entry's text is truncated to 120 characters with a trailing ellipsis. The payload always reports the true total alongside whatever is shown, so the footer states an honest count ("3 of 12 active, 5 of 47 next work") instead of a silent "+N more" row. Two paging mechanisms ship together: conversational paging (the skill re-invokes the producer with a larger `--limit-*` or `--all` when the user types "more"/"all", carrying no state on disk), and `--plain`, a plain-text, uncapped mode meant to pipe into a real pager (`less`).
- **Auto-mode contract**: `--json` still emits the machine readable manifest (`dispatchable_queue`, `human_only`, `next_big_thing`) that `plastic-auto` consumes; unchanged by intent 202. The plain ASCII cockpit (`continue`/`project <slug>`/`all`, no flag) also stays untouched. Roadmaps are the primary planning surface (intent 148): when a tier has a mid-flight roadmap, `plastic-auto` consults `scripts/roadmap-next` first and dispatches its frontier batch; the dashboard `dispatchable_queue` is the fallback, used only when `roadmap-next` reports `none` or `exhausted` (no roadmap, or nothing left to dispatch). The dashboard stays the state view, not the planning surface.
