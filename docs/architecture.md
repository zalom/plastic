# architecture

## overview

Plastic is an intent store plus a thin tooling layer over it. The store is plain files (folders, Markdown, YAML frontmatter) that capture desires and carry them through a fixed lifecycle; the tooling (the `plastic` command, hooks, scripts, agents, templates) keeps the store well-shaped and automates the deterministic parts. This document describes the system structure. For how the cycles actually execute (operational mechanics, harness detail), see [internals](internals.md). For the pitch and quick start, see the [README](../README.md).

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

- **Global store**: one per person, holding strategic intents (personal goals, research, framework work). Person-level configuration sits in the Plastic home, `~/.plastic/`: a preferences file (`config.yml`) and a project registry (`projects.yml`).
- **Project stores**: one per project, holding tactical intents (concrete work items inside that project). A project store root adds one settings file, `project.yml`, copied from `templates/project.yml`.

Each store root has exactly one `INDEX.md` and a `store/` folder holding one directory per intent. A store root can also hold a `roadmaps/` folder. A fresh install creates the stores layout, where every store root sits under `~/.plastic/stores/` and the global store is the root named `global`:

```
~/.plastic/
  config.yml
  projects.yml
  stores/
    global/
      INDEX.md
      roadmaps/
      store/
        ID--slug/
    {slug}/
      INDEX.md
      project.yml
      roadmaps/
      store/
        ID--slug/
```

So the global store is `~/.plastic/stores/global/store/`, and a project store is `~/.plastic/stores/{slug}/store/`.

Homes created before the stores layout use the legacy layout. There the global store root is `~/.plastic/` itself (`~/.plastic/INDEX.md` and `~/.plastic/store/`), and project store roots sit at `~/.plastic/projects/{slug}/`. Plastic reads the stores layout when `~/.plastic/stores/` exists, and reads the legacy layout when it does not. The installer bootstraps the legacy layout only when the home already holds a legacy `store`, `projects`, `INDEX.md` or `roadmaps` entry. An existing home keeps its layout until `plastic migrate stores` moves every store under `stores/`. Reinstalling does not move user data.

The rule of thumb: if the work changes a specific project's code it is tactical and belongs in that project's store; otherwise it is strategic and belongs in the global store. When in doubt, global. Stores are personal and local; the Plastic home is git-tracked locally but never pushed to a remote.

`varar/store-layout.md` checks fresh installation and legacy migration separately for
Claude Code and Codex. Its Ruby fixtures execute an npm archive in disposable homes,
including harness registration and public project and intent creation. These deterministic
checks supplement the live authenticated agent runs; they do not claim full doctor or
all-command acceptance.

### intent directory contents

Every intent is a folder named `ID--slug/` inside a store's `store/` folder. Lifecycle artifacts (spec, plan, checklist, outcome) always live in this intent directory in the store, never in the project repository.

```
ID--slug/
  ID--slug.md     # the intent file (its base name equals the folder name)
  spec.md         # the Why deliverable
  plan.md         # the How deliverable (planning)
  checklist.md    # the How deliverable (execution registry)
  outcome.md      # the Exec deliverable (a disposition: delivered|abandoned header at close)
  savepoint.md    # deterministic cycle-step ledger, written automatically
  graph.md        # the node graph `plastic intent step` runs (Goal, Decisions, Graph, Status)
  nodes/          # one file per graph node
  delivery.lock   # the delivery lock, present while a session owns the delivery
  revisions.md    # optional structural-maintenance audit trail (present only after maintenance)
  actions/        # action files
  resources/      # research, references, snapshots, diagrams
```

`plastic intent new` runs `scripts/new-intent`, which creates the intent file, `actions/`, `resources/`, the born `What` line in `savepoint.md`, and placeholder copies of `spec.md`, `plan.md`, `checklist.md`, and `outcome.md`. Each placeholder starts with `<!-- plastic:placeholder -->`, so a file that still carries that line is not a real artifact. The other files appear when the command that uses them first runs. At close, `plastic intent end` backfills `spec.md`, `plan.md`, `actions/ACTION_1.md`, and `outcome.md` from the record wherever a file is missing or still a placeholder.

Lifecycle artifacts use those exact reserved names and live directly in the intent folder, never in subfolders and never renamed. All other supporting material goes in `resources/`. State is not stored in a status field. The INDEX.md terminal sections are the canonical done marker (see "intent done and the end tail" below), and the stage is derived from which artifacts carry real content. `revisions.md` is not a lifecycle artifact: it appears only when structural maintenance relocated a misplaced section, file, or ref out of a delivered intent, so its existence signals structural (not conceptual) change.

### the session day ledger

Inside the global store folder sit two dot-prefixed paths (intent 297): `.sessions/`, one shared day ledger per calendar date, and `.tmp/`, a per-session scratch area. Both are invisible to every store walker precisely because of the leading dot, so neither one is, or ever becomes, an intent. In the stores layout the global store folder is `~/.plastic/stores/global/store/`; in the legacy layout it is `~/.plastic/store/`:

```
~/.plastic/stores/global/store/
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

The day id is the local wall-clock date, digits only with no hyphen, so it satisfies every id pattern in the store with no special case. One day directory is shared by every session that touches that day, project agnostic, with each checklist and savepoint line tagged by session and project. A day ledger has no `INDEX.md` entry. `SessionLedger` (`scripts/lib/session_ledger.rb`) performs every write to `checklist.md` and `savepoint.md` inside a day directory. `scripts/append-ledger` is its command-line front, and the hooks call the library directly.

### the session close path and the next-day sweep

At `SessionEnd` the `close` hook drops the session's never-acted-on pending lines, removes its
`.tmp/<session-id>/` scratch, and, if the session crossed midnight, files yesterday in the
background. The real backstop is the first boot of a new day: `hook-session-start` files every
unclosed prior day (backfilled `spec.md`, `plan.md`, `actions/ACTION_1.md`, `outcome.md` from the
ledger, open items carried into today, a `closed:` stamp), three days per boot at most.
`promote-session-item` turns one ledger line into a registered intent. See `docs/internals.md`,
"the session close path and the next-day sweep".

### the session branch model and session-commit

A verified checklist item becomes one commit through `scripts/session-commit` (intent 300), which resolves the repository containing `--cwd`, loads that repository's `flow:` setting from its `project.yml`, and applies the branch model: under `mode: direct` (the default) it commits to a session branch cut from the repository's own base branch and fast-forwards the base into that commit; under `mode: pull_request` it cuts a small branch and PR per item instead. The five flow knobs (`mode`, `base`, `branch_template`, `ticket_source`, `workspace`) are documented in `templates/project.yml` and validated by `scripts/lib/project_validator.rb`; `workspace: worktree` is an accepted value but not yet implemented, and degrades to `checkout` with a Note (see internals for why). `session-commit` is fail-open throughout: no repository, a detached HEAD, an unborn repository, a clean tree, an agent-owned branch, a refused checkout or push, a missing `gh`, or a rejected commit-msg hook all degrade to no commit plus one `Note` savepoint line, never a non-zero exit, and the same holds for a store or ledger write failure. Every outcome writes exactly one `Item` or `Note` line to the day's `savepoint.md` through `SessionLedger`. See [internals](internals.md#the-session-branch-model-and-session-commit-intent-300) for the mechanics.

## identity and the knowledge graph

Intents are addressed by Folgezettel IDs, following Luhmann's alternating convention. Assigning an ID requires only reading the existing IDs in the store:

- **Root intents** are sequential integers: `1`, `2`, `3`. The next root is one greater than the highest existing integer root.
- **Branches alternate number and letter** as they descend from the parent: `1` to `1a` to `1a1` to `1a1a`.
- **Sibling branches increment the final segment**: the first child of `14` is `14a`, then `14b`, then `14c`.

Whether to branch is a meaning decision: branch when the new intent cannot stand on its own without its parent; make it a root when it is independent, even if inspired by another intent (record the provenance in `sources`).

Intents form a double-linked graph, recorded in two mirrored places:

- **Frontmatter** (the machine-followable graph): `sources` are backward links (what influenced this intent) and `chain` are forward links (what this intent spawned). If `B` lists `A` in its `sources`, then `A` should list `B` in its `chain`.
- **Prose** (the human-readable graph): wikilinks under `## Links`, written `[[ID]]` or `[[ID|display text]]`. A tactical intent links back to its governing strategic intent with `[[global:ID]]`.

The frontmatter graph drifts over time as it is edited by hand, so two pieces of machinery keep it honest. `scripts/rebuild-graph` is a deterministic, idempotent maintenance tool that repairs the `sources`/`chain` graph across every store `StoreDiscovery` finds, in one pass: it dedupes each array, enforces the I-invariants one-directionally (a formative edge wins over a duplicate; missing in-store backlinks are added; relational forward links survive), and resolves cross-store refs against a multi-hop relocation map built from every store's `## Relocated` log, so a relocated target is repointed (and collapsed to a bare id when it now lives in the referring store) and a coincidentally-reused id never wins over a recorded relocation. Every change is written to a per-store before/after audit, and a re-run over a repaired store is a no-op. Complementing it, `doctor.rb` carries a `graph_cross_store_resolution` check that resolves every cross-store ref against the full store family (not just shape-checks it), so a well-formed ref pointing at a relocated or deleted intent is caught rather than silently accepted. See [internals](internals.md) for the module split and the named id-reuse hazard.

Each store's `INDEX.md` is a structure note, not a table of contents: it groups intents by meaning and records where each one sits in the person's attention (`## Active`, `## Future`, `## Clusters`, `## Abandoned`, `## Completed`). It does not record lifecycle stage, since that is derived from the files.

## component map

The tooling layer is thin and sits on top of the store. The parts that supply determinism do so by construction, never by judgement.

- **Skills**: no workflow skill ships in 2.0. Intents 304 and 372 retired the former `SKILL.md` packages into the `plastic` command and the `docs/help/*.md` chapters. The `skills/` directory still holds one shared fragment, `skills/_decision-tables.md`; the installer copies top-level `_`-prefixed Markdown fragments into `~/.plastic/` rather than into a skill directory. The general skill-authoring standard lives in the `skill-creating` and `skill-evaluating` skills at [zalom/agent-skills](https://github.com/zalom/agent-skills), and `docs/skill-authoring.md` keeps the Plastic-only rules.
- **Agents**: role files shipped in `agents/` that the installer syncs into each harness agent directory (Claude, Codex, Hermes) and tracks in that harness's manifest, so they prune on update and uninstall cleanly. Seven ship. In auto mode `plastic-enforcer` leads and reviews and `plastic-executor` builds, one team per intent. `plastic-node-work`, `plastic-node-research` and `plastic-node-verify` run the nodes the graph runner dispatches. `plastic-primary-advisor` and `plastic-secondary-advisor` are consultation agents. See `docs/help/agent-architecture.md` for the team model.
- **Hooks**: lifecycle event handlers, registered from one source of truth, `HookRegistry` (`scripts/lib/hook_registry.rb`). On Claude Code, SessionStart runs `session-start` (core doctor, boot banner, day summary) and `check-update`; UserPromptSubmit runs `capture`, which captures the prompt into the day ledger; PreToolUse runs `call-budget`; PreCompact runs `savepoint`, which saves intent state; SessionEnd runs `close`, which closes the session; Stop runs `stop`; MessageDisplay runs `message-display`; and one PostToolUse hook, `record` (`hooks/record` -> `scripts/hook-record`, on Write, Edit, NotebookEdit, and the six Serena edit tools), appends the savepoint line, refreshes the delivery-lock lease, and promotes the day-ledger line. The edit-path gates and the stage-transition gates were removed in 2.0 (intent 302): no hook gates a write on the lock or the stage, and doctor checks replace enforcement. Codex reaches a subset of these hooks through one dispatcher, `scripts/codex-hook`, registered in `~/.codex/hooks.json` from the same `HookRegistry`. The command `plastic hook EVENT` runs the same launcher for one event (`call-budget`, `capture`, `close`, `record`, `savepoint`, `session-start` or `stop`). It passes standard input through, prints nothing of its own and returns the launcher exit status unchanged. The registered hook entries still call the launchers directly (intent 372).
- **Scripts**: small deterministic Ruby programs that encode mechanical rules, for example assigning the next Folgezettel ID from the existing IDs in a store. Most `plastic` commands run one of them. `plastic intent new` runs `scripts/new-intent`, which allocates the id, creates the directory tree, renders the born-complete intent file, writes the placeholder lifecycle files, wires the reciprocal links, and self-validates (intent 60b); the command then adds the intent's line to `## Active` in INDEX.md. `new-intent` touches neither git nor project creation. `plastic intent verify` runs `scripts/verify-intent`, which merges doctor, an added-line em-dash diff guard, a diffstat, and an optional caller-supplied suite command into one verdict. `plastic intent end` runs `scripts/end-intent`, `plastic auto take` and `plastic auto lock` run `scripts/plastic-lock`, and `plastic intent step` and `plastic intent answer` run `scripts/runner`. `plastic feedback` runs `scripts/feedback-report`, backed by `scripts/lib/feedback_report.rb` (intent 174): it redacts secrets, writes a local report file, and builds a prefilled GitHub issue URL, with no send path anywhere in the code. Deterministic by construction.
- **Templates**: the fixed FORM of each artifact (its sections, their order, frontmatter fields, file name). Two people following the same template produce artifacts of identical shape even when the words differ. Deterministic by construction.
- **Conventions**: `PLASTIC.md` (installed at `~/.plastic/PLASTIC.md`) is the always-on core. On Claude Code, the installer's managed block in `~/.claude/CLAUDE.md` imports it with an `@~/.plastic/PLASTIC.md` line; on Codex, the managed block in `~/.codex/AGENTS.md` points at it. A dedicated Minitest test (`test/plastic_core_budget_test.rb`) holds it under 200 lines, 1,600 estimated tokens and 8,192 bytes, and `bin/plastic-bench` measures it (intents 223 and 313). Deeper doctrine ships as the `docs/help/*.md` chapters, which `plastic help TOPIC` prints on demand. Intent 372 retired the 1.x conventions skill and its chapter load lines.

For the operational detail behind these parts (determinism coverage, harness taxonomy, upgrade backlog), see [internals](internals.md).

### per-agent models

Every shipped agent in `agents/*.md` pins an explicit model alias and effort in its frontmatter, never `inherit`. The installer passes that frontmatter through unless an `agents.models.<name>` config override names another model, in which case the override is honored as written. The shipped tiers are:

| Agent | Model |
|---|---|
| `plastic-enforcer`, `plastic-node-verify` | `opus` |
| `plastic-executor`, `plastic-node-work`, `plastic-node-research` | `sonnet` |
| `plastic-primary-advisor`, `plastic-secondary-advisor` | `fable` |

The enforcer dispatches a plan reviewer before code and a post-execution reviewer when a review rule fires; neither reviewer is a standing agent file. Primary Advisor and Secondary Advisor are not lifecycle roles, and the auto pipeline never dispatches either. Both use Fable on Claude Code and Astra on Codex; Primary uses medium effort, and Secondary uses high effort. Every other agent ships at medium effort.

A project or the global store can override any agent's tier through `agents.models.<basename>` config; see [internals](internals.md) for the config precedence and the installer mechanism that applies it. The graph runner's dispatch line also names the model it resolved for each node, so a dispatch does not depend on the harness reading frontmatter.

### the advisor: two consultation agents, never injected (intent 185)

Two consultation role files are tracked separately from lifecycle tiers by `AgentModels::CONSULTATION_AGENTS`, and neither is dispatched by the auto pipeline. On Claude Code, `plastic-primary-advisor` and `plastic-secondary-advisor` both ship with `model: fable`, at medium and high effort. On Codex, both use `gpt-6-astra`, at medium and high effort. Secondary Advisor carries the full Operating Manual in its body. Model overrides use the same harness-scoped `agents.models.<harness>.<name>` mechanism as every other agent.

The `plastic-agent-advisor` skill was the front door until intent 372 retired it; `plastic help advisor-protocol` now carries when consulting is worth the money, and the configured advisor agent is called directly. Lifecycle agents and Primary Advisor ship at medium effort. Secondary Advisor ships at high effort. `agents.efforts.<harness>.<name>` is the explicit override, with project config over global.

Config uses keys matching `InstallerCore::DEFAULT_AGENTS` exactly (`claude`, `codex`, never `claude_code`). `advisor.enabled: false` skips both advisor agents on every harness. `advisor.claude.default` names an agent, never a model. Install asks which advisor is the default: Primary Advisor at medium effort, or Secondary Advisor at high effort. An unset value resolves to Primary Advisor. Installer flags are `--no-advisor` and `--advisor VALUE`, where `VALUE` is an agent name or the `primary` or `secondary` shorthand. Retired agent values migrate on install and update.

`agents.models` is harness-scoped from this release: `agents.models.claude.*` and `agents.models.codex.*`, with the pre-existing flat form (`agents.models.<name>: value`, no harness nesting) still honored as the claude harness, and nested winning over flat for the same agent. `AgentModels.models_section(config, harness:)` implements this: for `harness: "claude"` it merges the flat scalar entries with the `claude` sub-hash (nested wins); for any other harness it reads ONLY that harness's own nested sub-hash, never the flat entries. This closes a real latent bug: previously the same override map fed both `install_agents`' Claude frontmatter rewrite and `generate_codex_agents`' TOML `model` line, so a literal Claude model id set under the flat form could leak straight into a Codex config. `install_codex` now calls `agent_model_overrides(harness: "codex")`, so a model named under `claude` is never emitted to `codex`; a regression test (`test_agent_model_overrides_never_leaks_a_claude_model_id_into_codex`) pins this. Stage-agent tier translation to Codex reasoning effort (`AgentModels::EFFORT_BY_ALIAS`) is unchanged by this scoping.

`InstallerCore#generate_codex_agents` renders every shipped role, including consultation agents. `advisor.enabled: false` still omits both advisor roles on every harness.

Codex per-role model identity (intent 186): Codex has no vendor alias layer, so `AgentModels::CODEX_MODEL_BY_ALIAS` centralizes every Codex model id in one place, paired with the existing `AgentModels::EFFORT_BY_ALIAS` tier. A generated Codex agent TOML for a tier alias carries both lines, model first:

| Tier | Codex model | Reasoning effort |
|---|---|---|
| `opus` roles | `gpt-5.6-sol` | `medium` |
| `sonnet` roles | `gpt-5.6-terra` | `medium` |
| `haiku` roles | `gpt-5.6-luna` | `medium` |

Model and effort are shipped defaults, independently overridable through `agents.models.codex.<name>` and `agents.efforts.codex.<name>`. A literal Codex model ID still receives medium effort unless effort is explicitly overridden. Primary and Secondary Advisor TOMLs both use `gpt-6-astra`, at medium and high effort respectively.

### qmd search integration

QMD is an optional, recommended local markdown search engine layered over the stores. Plastic functions without it (ripgrep over the store files is the fallback), so the integration adds search without becoming a dependency. The topology is one collection per store in the default qmd index, all `plastic-` prefixed: `plastic-global` for the global store and `plastic-<slug>` for each project store (slugs from `projects.yml`). Plastic delegates all index mechanics to the qmd CLI through a single helper (`scripts/lib/qmd_sync.rb`, exposed as the `scripts/qmd-sync` CLI, with verbs for detect, register, reindex, status, and a read-only `search`) and never reimplements qmd commands. Index mutation is tied to lifecycle events only, never ad-hoc. In 2.0 the session-start hook suggests `qmd-sync register --all` when stores are not indexed, and only the internal `scripts/promote-session-item` reindexes. `plastic project new` registers no collection, and no public close path reindexes: the reindex step `scripts/end-intent` names lived in a retired skill. This is a known gap. Session start is report-only and never mutates the index. Query craft itself is owned by the installed `qmd` skill, not by Plastic.

`PLASTIC.md` carries no tool recommendation: it names only the `plastic` command. The per-prompt power-tools hook that used to repeat a QMD line was removed in 2.0 (intent 309), along with its decision module. When QMD is present, the session-start hook adds one report-only line to the model context: the number of indexed Plastic collections, or a hint to run `qmd-sync register --all`. Tool presence is computed by `scripts/lib/power_tools.rb` (`PowerTools.qmd?`, `PowerTools.serena?`, `PowerTools.enola?`: PATH and marker-file walks with no subprocess), and doctor's readiness checks call it for Serena and Enola. Intent 225 measured per-prompt hit injection at 0.24 intent-level recall@3 against a plain ripgrep control at 0.18, while agent-driven `qmd query` scored 0.71, so intent 246 removed the injection first and 309 the reminder. `QmdSync.search` is untouched and still backs the `scripts/qmd-sync search` CLI verb.

### intent born-complete validation

A single validator library, `scripts/lib/intent_validator.rb`, defines whether an intent is born complete (every required frontmatter field present, and `sources` and `chain` well-formed arrays of id references (bare ids, or cross-store references like global:1a2)). It is the only definition of that contract. It is exposed as the `scripts/validate-intent` CLI (exit 0 when complete, non-zero with a report otherwise) and consulted by both the `plastic intent new` command (a self-verify step after the write) and doctor (the `frontmatter_fields` and `frontmatter_valid` conventions checks). Intents are created only through `plastic intent new` and never hand-authored, so completeness rests on machinery rather than on agent discipline.

### project store provisioning

Project store creation has a single source of truth: the `scripts/provision-project-store` verb, backed by `scripts/lib/store_provisioning.rb`. It is pure filesystem and idempotent. It makes the store directory `store/` under the project root (`~/.plastic/stores/{slug}/store` in the stores layout, `~/.plastic/projects/{slug}/store` in the legacy layout). Then it writes, only if missing, `.gitkeep` in the store directory, and `INDEX.md` (from `templates/index.md`) and `project.yml` (from `templates/project.yml`) in the project root. It requires the project to already be registered in `projects.yml` (an unregistered slug exits non-zero and creates nothing) and performs no qmd mutation, so any caller (including a doctor fix) stays deterministic. `plastic project new` calls it, then runs `validate-project`. `plastic doctor` reports a missing store for an already-registered project; the internal `provision-project-store {slug}` creates it, and registering its QMD collection stays a separate, optional `qmd-sync register` step. Doctor's additive `project_store_dir` check warns (fixable) when a registered project's store directory is missing, naming `provision-project-store {slug}` as the fix.

## session boot

Boot is owned by hooks, so it runs by construction on every session start, not as prose a skill follows (intent 36a):

1. **Core doctor**: `hook-session-start` runs `doctor.rb --core` in-process, reusing the `Doctor` class so there is one source of truth for core health. The core check is binary (pass or error, never warn): it compares every core file against the SHA256 recorded in the install manifests (`~/.plastic/manifest.json` for global scripts and PLASTIC.md; `~/.claude/plastic/manifest.json` for agent-side files), and also confirms hooks are registered, scripts are executable, and the installed version matches.
2. **Load context**: the hook does not inject `PLASTIC.md` (intent 341). The harness loads it through the installer's managed instruction block (see Conventions above). The hook reads the store INDEX.md and projects.yml, detects the current project by matching the working directory, and adds the project banner, the QMD line, deprecation and update notices, the first-boot sweep result, and the day summary. Deeper doctrine is printed on demand by `plastic help TOPIC`, not primed at boot.
3. **Boot banner and version**: the result of the core check drives a binary banner. It names the installed version and ends in `doctor --core run: success` on pass, or `doctor --core run: error` plus a pointer to doctor on error. The banner is emitted on both the `hookSpecificOutput.additionalContext` channel (model-facing) and the top-level `systemMessage` channel (visible in the user's terminal). One `BootBanner` renderer feeds both channels so they cannot drift (intent 54). The hook never blocks (always exits 0).
4. **Statusline**: the `plastic-statusline` command renders the statusline. It is not a hook event: the installer writes it as Claude Code's `statusLine` setting, and only when the install-time choice below selects Plastic's line.

Install-time statusline choice is separate from the render-time hook above: `InstallerCore#statusline_choice` decides, once per install, whether to write Plastic's statusline over an existing one. A fresh settings file with no statusline gets Plastic's line with no prompt. An existing non-Plastic line triggers a keep-or-switch prompt in an interactive session, honors `--statusline keep|plastic` to skip the prompt, defaults to keeping the user's line in a non-interactive session, and is never re-asked on `--reinstall` (a repair keeps whatever is already configured). `merge_claude_hooks` still backs up the prior line to `~/.plastic/.cache/original-statusline.json` regardless of the choice, so a later switch or an uninstall can restore it.

`plastic status` and `plastic continue` then orient the session. Neither runs the health check, loads core, or sets the statusline, since the hooks already did. `plastic continue [--project SLUG]` prints the project, its store root, its active intents, and its liveliest roadmap with that roadmap's frontier batch. It then names one next step: the frontier's step when a roadmap exists, else `plastic intent show ID` for the first active intent, else `plastic help`. `plastic next` prints the same next action on one line. Both read it through one `Frontier` class over `RoadmapQueue`, which ranks roadmaps deterministically rather than by eye (intent 148).

Each roadmap carries a ledger (intent 134): a name-paired `roadmaps/<slug>.savepoint.md`, the machine counterpart to the human `## Log`, which follows its roadmap into `roadmaps/archived/` on close. `plastic roadmap log SLUG EVENT "TEXT"` appends to it (the events are created, dispatched, parked, merged, release, handoff, closed, added, reordered, wave and batch), and `RoadmapQueue` reads its last line as the roadmap's last-event time when it ranks roadmaps. The ledger is never a status source: `INDEX.md` stays the source of intent status.

## the delivery lock and the record hook

The delivery lock (`delivery.lock` in the intent directory) names the session delivering an intent, as owner or delegate; `scripts/lib/arm.rb` behind `plastic auto take` (which runs `plastic-lock arm`) is how a team takes and gives back an intent. A lock held by another session is refused with exit 3 and a public hint, never taken over.

Removed in 2.0 (intent 302): the edit-path gates (edit, bash, code, lock, links), the create gate, and the stage-transition gates. No hook blocks a write any more; the record hook is the only write-path hook, and doctor checks (intent 308) replace enforcement.

The record hook (`PostToolUse`, on Write, Edit, NotebookEdit, and the six Serena edit tools) derives the intent directory directly from the written file path (it walks up to the first ancestor that looks like `.../store/ID--slug`) and appends the savepoint line there directly from the path, so an unset session or a headless background run never skips the ledger. For a write inside a locked intent directory it also refreshes the delivery-lock lease for the owning session (`Lock.heartbeat`, which refuses any session that does not hold the lock). For a project-file write it promotes the session's pending day-ledger line and calls the session-commit seam (see the session branch model above).

Session resolution feeds the arm, disarm, and repair paths and the spawn preamble; it has a fixed precedence (intent 52). Claude Code does not export a session id env var into the hook environment; it passes `session_id` on the hook stdin JSON, so the hooks parse it out of stdin (in Ruby, never in bash). The resolver picks the first non-empty of: the stdin `session_id`, the `CLAUDE_CODE_SESSION_ID` environment variable (the headless/background id), and a derived `auto-<digest>` key (a short hash of the store path plus the intent id). The derived key is deterministic, so a session-less arm and a later session-less check resolve to the same session key. A null session can never be persisted to `delivery.lock`.

## worktree isolation and the delivery lock

Removed in 2.0 (intent 302): the edit-path gates (edit, bash, code, lock, links), the create gate, and the stage-transition gates are gone with their code. The paragraphs and list items of this section that described them were removed with them; what remains is the `record` hook (savepoint line, lock heartbeat, day ledger) and the doctor checks that replace enforcement (intent 308).

An intent whose delivery touches code runs in its own git worktree, and an intent's delivery is single-owner: exactly one session develops it at a time. Both properties are owned by Plastic, not the harness (intents 73c and 108). The lock is a durable `delivery.lock` JSON file inside the intent directory, acquired atomically (O_EXCL) at arm time. Its `owner_session` is the sole authorization identity. Controller provenance (`harness`, `agent`, `model`, `thread`, and `mode`) is descriptive only, accepts explicit values from the harness, and is never inferred from transcripts or paths; legacy omissions render as `Unknown`. Liveness is a lease: write-path hooks refresh the file mtime on owner activity, and that mtime is the sole heartbeat and freshness truth against the 1800-second TTL. A fresh foreign lock means back off; a stale one is taken only by explicit takeover, which appends an audit line to savepoint.md and replaces the prior controller. Rearming the same session refreshes known provenance without changing authority. The internal `plastic-lock` CLI exposes the lock verbs (`arm`, `status`, `who`, `fix`, `release`, `reclaim`, `delegate`, `claim`, `release-claim`), and the public `plastic auto lock` command runs its `status`, `fix` and `release` verbs. `fix` is the idempotent repair; it also migrates legacy lock files that still carry a pid. `who` is a read-only durable-files view of controller, mtime heartbeat, delegates, and claims. `Arm.delivery` is the hash `Worktree.provision`, `release`, and `finish` take, and it records the code worktree path and branch plus a `provisioned` flag.

Provisioning is deterministic and cwd-independent. Plastic resolves the project repo from `projects.yml` and runs `git -C <repo> worktree add`, so it never relies on the current directory (this is the fix for the cwd-not-repo-root gap that silently degraded the harness worktree tool). One worktree is created per project intent, named `{id}--{slug}`: the code worktree at `<repo>/.claude/worktrees/{id}--{slug}` on branch `plastic/{id}--{slug}`, where all code edits happen. A second, store worktree used to exist; intent 178 retired it, and store-write safety for lifecycle-doc commits now comes from intent 197's branch-from-main plus scoped-commit mechanism. Creation is idempotent: an existing worktree path is reused, not re-created. Disarming releases the worktree (`git worktree remove` then `git worktree prune`) and clears the block.

Provisioning fails open: for a pure research or decision intent in the global store, or a repo that is not a git work tree, the code worktree is skipped, `provisioned` stays false, and the fall-back is logged to stderr (never silent). Such intents still get the lock.

The delivery lock arbitrates at the whole-intent grain only: two writers that both hold it, whether two delegates or two subagents sharing one session id, both pass this check on the same lifecycle file. Intent 111 adds a per-artifact claim token underneath it (`.claims/<artifact>.claim`, one small JSON file per artifact, scoped strictly to that intent's own artifact) as a coordination record a team lead takes and releases through `plastic-lock claim`; since 2.0 (intent 302) nothing enforces a claim at write time, and live claims are visible in `plastic-lock status`. See `docs/internals.md` for the full mechanism.

Controller, delegate, and claim records answer different questions. The controller owns the intent, a registered delegate is a separately authorized child session, and a claim identifies the current writer for one artifact. Delegate activity status (`active`, `finished`, or `failed`) is descriptive and does not remove the session from the string-array authorization list. A delegate remains authorized until a separate removal mechanism exists. Finished and failed activity history is bounded to the 20 most recent terminal entries.

### intent done and the end tail (intent 93)

Done is one law with three signals that must agree. The INDEX `## Completed` or `## Abandoned` section is the single canonical terminal marker (the store-wide ledger a fresh session reads first), so it wins on any conflict. `outcome.md` is the deliverable-exists signal, mandatory at every terminal (delivered and abandoned alike) and self-declaring through a `disposition: delivered|abandoned` frontmatter header. The savepoint `Done delivered|abandoned` line is the audit echo. When the three disagree, INDEX is authoritative and `doctor` (the `done_signals` check) reports the mismatch.

The audit echo can itself drift, so a pure, disk-only detector (`Savepoint.savepoint_phantom_lines`, intent 134; the ledger code lives in `scripts/lib/savepoint.rb` since intent 303) checks it: a savepoint line is a phantom when its file-landing milestone is absent or still a sentinel placeholder, its `(stage, milestone)` pair is a duplicate, or a state line's stage prerequisite is missing on disk. Doctor's `savepoint_truthful` check (in `done_signals`) reports phantoms as a warning, never a failure. For a live (INDEX Active) intent its fix hint names `Savepoint.rebuild_savepoint`; a terminal (Completed/Abandoned) intent is immutable, so a phantom there stays report-only.

The End tail runs in a fixed order: `outcome.md`, then the INDEX terminal move, then the savepoint `Done` line, then the commit, then disarm (worktree release, then `Lock.release`). The design put a QMD reindex last, after disarm, so the index never references a released lock; `scripts/end-intent` does not run it in 2.0, and no public close path reindexes (a known gap). No hook freezes the intent directory after the lock is released: since intent 302 no hook gates a write on the lock or the stage, and doctor's `done_signals` checks report drift instead.

Since intent 188, `scripts/end-intent` performs disarm itself, as its own step 5 after the
outcome/INDEX/savepoint/commit steps commit: the script's exit code 0 now means both "the
intent is closed" and "its delivery lock is gone," rather than the second half being left to
a separate one-liner an agent had to remember to run. A pre-flight guard resolves the calling
session and refuses the whole run before anything is written when a live foreign session
holds the lock, and reclaims a stale foreign lock automatically (audited to savepoint.md). A
dirty code worktree refuses before removal (rather than the existing force-remove path
silently discarding uncommitted changes), unless an explicit `--discard-worktree-changes`
flag overrides it. `end-intent`'s own INDEX-move parser and `IndexEntry.active?` now share
one matcher that accepts a real em dash or a plain hyphen as the id/title separator on read,
while every write still emits the real em dash.

A delivered close requires its code to be merged already. Before any write, `end-intent`
checks with `git merge-base --is-ancestor` that the code is an ancestor of the repo
checkout's current branch. It checks the HEAD commit of the code worktree, whether that
worktree is on its own branch, a renamed branch, or a detached HEAD. It also checks the code
branch, which still matters after the worktree is removed. The checkout must be on a branch
other than the code branch. If the code isn't merged, or Git can't answer, `end-intent` and its dry run exit 9 and change nothing, and `plastic intent end` reports that as exit 1 with the reason. `end-intent` never
merges: the owner merges or releases the work and runs the close again. An abandoned close
and a store-only intent skip the check.

## status and the dashboard

`plastic status` prints one row per store this machine holds: the store's slug, its count of active intents, and their ids (for example `global  2 active  7, 9`). It then names one store to continue: the store whose repository holds the working directory when that store has active work, else the store with the most active intents, else `plastic help` when no store has active work. `--json` returns the same rows as a `result` hash of slug to summary. It renders no board, table, prose summary or ranking.

`scripts/dashboard.rb` still ships as an internal, read-only script. The `capture` hook runs it when a prompt is exactly `continue`: it adds the plain-text cockpit (`dashboard.rb continue`) to the model context, and a banner built from `dashboard.rb continue --data` to the user's terminal. The script's modes are:

- `--data`: one JSON payload with the capped active list (3 by default, `--limit-active N`), the ranked next-work list (5 by default, `--limit-next N`), and the true totals; `--all` lifts both caps, and entry text is truncated to 120 characters.
- `--json`: the machine-readable manifest (`dispatchable_queue`, `human_only`, `next_big_thing`).
- `--plain`: the full, uncapped board as plain text, meant to pipe into a pager.

Same store state gives the same output regardless of model. Roadmaps are the planning surface: `plastic next` and `plastic continue` read the roadmap frontier through `RoadmapQueue`, and the dashboard stays a state view.

## CLI output and progression

The command layer owns project scope and next actions. The command table is `scripts/lib/cli/table.rb` (intent 363): one frozen hash maps each command name to its file, its class, and the line `plastic help` prints. Help topics are the `docs/help/*.md` files, printed by `plastic help TOPIC`. Every command parses `--json` and `--project SLUG` through the shared `Command` parser, except the installer verbs (`install`, `update`, `uninstall`, `rollback`), which accept only their own flags, and `plastic hook EVENT`, which hands the event straight to its launcher. Emitted commands retain the resolved project. Repository paths and store paths both resolve scope, including filesystem aliases.

JSON commands capture script stdout under `result.output` and emit one document.
Diagnostics remain on stderr. Direct intents use their specification, plan, and
checklist to select work. Graph execution first checks ownership and names the
public lock command when ownership is absent. Completed intents have no next
action. A Future index entry does not remove an explicit roadmap block.

Without a roadmap, both `next` and `continue` select the first active intent.
Graph steps accept repeated `--return NODE=PATH` arguments and a harness override,
so the public command can complete the runner's dispatch and absorption cycle.
Conversation sessions still require explicit owner approval for inline delivery;
`auto take --allow-inline` carries that approval to the existing lock guard.

### Safe package transitions

The executable resolves its own package root, even when an older updater passes
an inherited package path. Update and rollback clear that inherited path when
launching npm and verify the installed version before reporting success.

Homes using `stores/` cannot switch to versions before `2.0.0-alpha.28`, which
introduced that layout. This refusal happens before installation or hook cleanup.
Legacy homes retain their existing rollback behavior.

`plastic project links` saves its audit under the current global store's
`resources/` directory. Its dry-run writes no files. Use
`plastic doctor --agent claude`, `--agent codex`, or `--agent hermes` to select
the harness being diagnosed.

### Closing checks

`plastic intent end --delivered` refuses an untouched scaffold. An untouched
scaffold has only placeholder lifecycle files, no action or graph, no savepoint
entries after the first What line, and no changes in its code worktree. Close it
with `--abandoned`, or do the work first. Legacy intents with missing lifecycle
files still close through the backfill.

`--dry-run` runs the same refusals as the real close and writes nothing. It
refuses an untouched scaffold, unmerged code, a hollow delivered report, and a
dirty code worktree. A passing dry run ends with `next: none`.

A real delivered close refuses an untouched scaffold and unmerged code before
it writes anything. The hollow-report refusal runs later, after outcome
generation and the backfill, so a close it refuses may already have written
`outcome.md` or action files. INDEX.md, the savepoint `Done` line, and the store
commit stay untouched in that case. A dirty code worktree refuses at disarm,
after the store commit. `plastic intent end` reports each of these refusals as
exit 1 with the reason.

### Project registration

`plastic project new` accepts a slug of lowercase letters, digits and hyphens
that starts with a letter or digit. `global` is reserved for the global store.
Any other slug exits 2 before anything is written. A directory already in
`projects.yml` under another slug is refused with exit 1, naming that slug.

### Session commits on delivery branches

`plastic session commit` never commits on an intent's delivery branch or
worktree. Its note now names the real delivery lock of that intent: held by
another session, held by this session, or not held at all. It no longer
reports an agent lock that does not exist. The `next:` line no longer implies
that a commit landed; the printed line above it says whether one did.

### Sync preview

`plastic sync` rebuilds `work_graph.db` and `references.db` on every run. When
either is missing, the plan names it under `build`. The preview and the sync
now report the same work, and "nothing to do" means nothing is missing.

### Rendering

`plastic render` leaves out a leading YAML frontmatter block. A later `---`
line is still a horizontal rule.

### Roadmap health and selection

A roadmap whose graph has a cycle cannot compute a frontier. It now ranks after
every healthy roadmap, so `plastic next` and `plastic roadmap next` pick a
healthy one first. It is still reported as an error when nothing else is left.

`plastic roadmap next` shows the tied roadmaps when several are equally live.
`plastic roadmap check` names a cycle and every graph id that no batch lists.
`plastic roadmap show` adds a warning row for either problem and points at
`plastic roadmap check`.

### Node dispatch and the finished graph

A dispatch line names the agent type for the node's kind. A research or verify
node has no worktree, and its dispatch line and input both say it is read-only.
When a step leaves every node in a finished state, `plastic intent step` names
`plastic intent verify ID` as the next command instead of another step.

## History: the 1.x skill design

This section describes Plastic 1.x. It is not current behavior.

- **Skills.** In 1.x the workflows were `SKILL.md` packages: direct-mode routing, intent creation, brainstorming, planning, executing, releasing, indexing, and a conventions router skill whose chapters each consuming skill loaded on demand. Intents 304 and 372 retired them into the `plastic` command and `docs/help/*.md`.
- **Direct mode.** A booted session rested in direct mode, and the `plastic-direct` skill routed each prompt on a time estimate. A change of about five minutes ran inline, a vague prompt was offered a thinking intent, and a larger change was offered a dedicated intent. Intent 372 retired the skill.
- **Stage agents.** Each lifecycle stage had its own agent: discovery for What, brainstorming and spec agents for Why, a planner for How, the executor for Exec, and a curator for Done. Intent 304 removed all of them except `plastic-executor`.
- **The dashboard skill.** A prose skill filled Markdown board templates from the `dashboard.rb --data` payload. It was retired with the other skills.
- **The continue router.** A continue skill chose among a project route, an intent route that read the intent's savepoint first, and a roadmap route. `plastic continue` replaced it.
