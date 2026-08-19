# Plastic: Conventions

> **This file is maintained by Plastic.** It will be overwritten when the
> plugin is updated. Do not modify it: your changes will be lost.
> For project-specific rules, use `AGENTS.md` instead.

Deeper doctrine lives in the `plastic-conventions` skill's chapters
(`plastic-conventions > references/<chapter>.md`); read the one that matches your task on demand,
it is not injected at session start.

## Two Processes

| Process | Scope | Type | Actor |
|---|---|---|---|
| **Build → Observe → Repeat** | The system | Continuous loop | Coordinator |
| **What → Why → How → Exec** | One intent | Finite lifecycle | Agent |

B→O→R is the Coordinator's heartbeat. W→W→H→E is what happens inside each intent.
The connection: an intent's `## Insights` feeds the Coordinator's Observe phase.

## What is an Intent

A directory in the store containing `{ID}--{slug}.md` and optional supporting files.
It represents a desire: something a human or agent wants to accomplish, explore, or understand.
The unit of work in Plastic is always an intent, never a ticket.

```
store/
  ID--three-to-five-words/
    {ID}--{slug}.md       # required - the intent itself
    spec.md               # optional - specification (Why deliverable)
    plan.md               # optional - implementation plan (How deliverable)
    checklist.md          # optional - execution registry (How deliverable)
    outcome.md            # detailed result (Exec deliverable) - mandatory at a terminal (Completed and Abandoned alike)
    actions/              # optional - real action files (How deliverable, at least one required)
    resources/            # optional - research, references, screenshots, diagrams
    savepoint.md          # optional - deterministic cycle-step ledger (auto-written)
    revisions.md          # optional - append-only structural-maintenance audit trail
```

Lifecycle files (`spec.md`, `plan.md`, `checklist.md`, `outcome.md`) have defined
roles. Supporting artifacts that aren't lifecycle deliverables (research reports,
reference docs, external API snapshots, screenshots, diagrams) go in `resources/`.
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

- Context contract: load `sources` strongly (they are what the intent was built from);
  traverse `chain` lightly for discovery. See
  [`how-plastic-sources-and-chains-intents.md`](https://github.com/zalom/plastic/blob/main/docs/concepts/how-plastic-sources-and-chains-intents.md) for the full model.
- IDs use Luhmann's alternating convention: `1` → `1a` → `1a1` → `1a1a`
- Multiple branches increment: `1a`, `1b`, `1c`

See `plastic-conventions > references/knowledge-graph.md` for the linking doctrine: the tiers
of influence (sources/chain/tags) and the `## Links` projection rules.

## Lifecycle Stages

| Stage | Section | Deliverable | Detail |
|-------|---------|-------------|--------|
| **What** | `## Intent` | `{ID}--{slug}.md` | `plastic-intent-creating` |
| **Why** | `## Context` + Decisions | `spec.md` | `plastic-intent-brainstorming` enriches Context/Decisions; `plastic-intent-speccing` writes `spec.md` |
| **How** | Planning | `plan.md` + `actions/ACTION_N.md` (at least one) + `checklist.md` | `plastic-intent-planning` |
| **Exec** | Execution | `outcome.md` | `plastic-intent-executing` |

Invoke a skill for your harness: Claude Code uses the slash form (`/plastic-intent-creating`);
Codex CLI uses a dollar prefix instead (`$plastic-intent-creating`), and may also select a skill
implicitly by matching its description. Skill names elsewhere in this document are given bare
(`plastic-intent-creating`); add the prefix for your harness.

`## Insights` is the append-only log of durable discoveries captured throughout ALL stages.
An insight is a discovery worth keeping for later reads: novel, or old but newly relevant,
surfaced at any stage (What, Why, How, Exec). It is the most interesting residue of an
intent, the part a future reader most wants. **Append-only means newest entry at the bottom;
never prepend.** This ordering is a hard convention: Insights are the semantic trace of an
intent, and a consistent newest-last order keeps that trace readable across every intent.

Every entry leads with a fixed, machine-parseable prefix `{utc-iso8601} · {stage} · {author}`,
for example `2026-06-24T08:13:05Z · Why · plastic-brainstorming (autonomous)`. The UTC ISO8601
timestamp (to the second, trailing `Z`) is the same convention the savepoint ledger uses, so
the store has one timestamp convention. This per-entry prefix is not prepending the entry:
entries stay append-only, newest at the bottom; the prefix only stamps each line with when,
which stage, and who.

The blessed write path is the `insight-append` helper
(`scripts/insight-append <intent_dir> <text> --stage S --author A`), which ships with every
install and update, formats the prefix, validates it, and appends at the bottom. Hand-editing
`## Insights` is an escape hatch; the helper is the default so the format cannot drift.

See `plastic-conventions > references/lifecycle-and-savepoints.md` for the subagent
report-home contract (how an insight reaches the intent when the writer cannot write the file
itself) and `savepoint.md`'s role.

## Tiers (proportional auto sizing)

Auto mode sizes every intent S/M/L at Why: S = single mechanism or file cluster (hours);
M = one subsystem (about a day); L = cross-cutting or novel design.

Tier is recorded as a `Tier: S|M|L` line at the top of spec.md. It is convention-only,
read by the orchestrator, not enforced by any gate or by doctor.

Settledness is recorded separately, as a `Settled: yes (<reason>)` line directly beneath the
`Tier:` line, above the `# Spec:` heading. It records that a design has already done its
thinking, so a later stage can trust it without deriving it again. An absent line means not
settled; there is no `Settled: no` form. Settledness and scope are independent, so a large
intent can be settled and never becomes a smaller tier. `scripts/lib/spec_header.rb` is the
only parser of both lines; nothing else reads the grammar.

See `plastic-conventions > references/tiers-and-dispatch.md` for topology by tier, what never
gets cut, and guided mode.

## Agent Models and Dispatch (intent 116)

| Stage | Agent |
|---|---|
| What | `plastic-intent-discovery` |
| Why | `plastic-brainstorming` + `plastic-spec-specialist` |
| How | `plastic-planner` |
| Exec | `plastic-executor` |
| Done | `plastic-intent-curator` |

See `plastic-conventions > references/tiers-and-dispatch.md` for the advisor, model
configuration, the dispatch contract, and the spawn preamble.

## Operational Skills

- **`plastic-feedback`** turns a described Plastic quirk, bug, or feature idea into a redacted
  local report file and a prefilled GitHub issue URL; only the user submits it. If the user hits
  a Plastic quirk, bug, or missing feature, offer to invoke the plastic-feedback skill yourself
  instead of waiting to be asked.
- **`plastic-doctor`** checks installation health across three scopes: core, store, and full.
  See `plastic-doctor/SKILL.md` for the contract.

## Releases and Versioning

Plastic ships as versioned releases; a release is a collection of intents. Run
`plastic-releasing` for the full flow (version bump, tag, GitHub release, npm publish).
Deprecations are declared in `deprecations.yml` and shown at SessionStart.

## Gotchas

- **Artifacts go in the intent directory.** Never create `docs/plans/`,
  `docs/specs/`, `researches/`, or similar. All meta-artifacts go in
  `~/.plastic/store/ID--slug/` or the project store equivalent.
- **Code goes in the project. Everything else goes in the intent.**
  Plans, specs, checklists, savepoints: all in the intent directory.
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
- Next ID: `ruby ~/.plastic/scripts/folgezettel-id <parent_id> <store_path>`

See `plastic-conventions > references/knowledge-graph.md` for the branch-vs-root semantic
decision: when to branch versus start a root.

## INDEX.md

A Zettelkasten structure note, not a table of contents. Clusters by meaning.

Sections: `## Active`, `## Future`, `## Clusters`, `## Abandoned`, `## Completed`.

For index maintenance, use `plastic-store-indexing`.

One-line entry convention. Each index entry is ONE line: `- [<id> <terse title>](<dir>) <tags>`.
The title is the title, not a summary: aim for about 80 characters, no multi-sentence
descriptions. This is a self-check, not a gate.

## Roadmaps

A roadmap is a named, ordered, delivery-side collection of intents. Create, order, close, and
consume one with `plastic-roadmap`; see `plastic-conventions > references/roadmaps.md` for the
full format.

## Rules for Skills

ALL work flows through intents.

1. Before starting work, check INDEX.md for active intent. If none, create one.
2. Skill output (spec, plan, checklist) goes in the intent directory.
3. On completion, capture observations in `## Insights`.
4. When done, write `outcome.md` + `## Outcome` summary. Update INDEX.md.
5. Researches are intents. No separate folder.
6. Intents are created only via `plastic-intent-creating`. Never hand-author an intent file. The skill self-verifies the written intent with `scripts/validate-intent` before announcing or committing, so every intent is born complete. `--intent` text is escaped for double quotes and backslashes before it lands in frontmatter, so free-form text is safe to pass as-is, and a reciprocal `chain:` append preserves the target intent's existing flow- or block-style entries.

## House Style (self-check)

The agent is the heaviest contributor to the transcript, so terseness pays every turn. These
are pre-send self-checks the agent applies to its own output. They are not gated.

- Answer or decision first. Lead with the result, then support it.
- Bullets over paragraphs.
- No preamble, no end-recap. Do not restate the question or summarize what you just said.
- One question-cluster at a time when asking the human.
- Reasoning goes in the thinking channel, not duplicated into the visible reply. This keeps
  the human's visibility into your reasoning without paying for it twice in the transcript.

Active-intent cache rule. For the intent under active development you already hold its
delivered artifacts in your own context: prefer revisiting that in-context memory (hit the
cache) over re-reading them from disk, which only widens context. QMD is for OTHER or indexed
intents, not for re-reading what you just wrote. Pairs with `/clear` plus savepoint-resume
hygiene after each intent. Advisory self-check, not hard-verifiable.

## Tabular-First Reporting (intent 160)

**Default.** Tabular layout is the default shape for three surfaces: What-stage discovery
deposits, all research reports, and all agent reporting or presentation surfaces.

**Calibration.** Tables are REQUIRED for any listing or discussion of intents, and for
explaining complex data, comparisons, or multi-factor reasoning. This is NOT a blanket
tables-everywhere rule: simple data stays prose, and tables must not be overused.

**Bullets-limit.** Use bullets only when a table genuinely does not fit the content, and
never more than 3-5 items.

**Exception.** The EM-to-CTO human briefing (`skills/auto/references/human-report-contract.md`)
keeps its deliberate prose shape (fixed State/Risk/Call, single item, nothing to tabulate) and
is exempt from this rule.

## QMD Search

QMD, Enola, and Serena are recommendations, not obligations. The deterministic entry point
is `scripts/qmd-sync` (detect, register, reindex, status, search). Intent delivery reindexes
the store; see `plastic-conventions > references/gates-and-enforcement.md` for gate
mechanics.

## Transition Gates

| Transition | Trigger | Gate |
|---|---|---|
| What → Why | `spec.md` written | (none) |
| Why → How | `plan.md` + `actions/ACTION_N.md` (at least one) + `checklist.md` | `spec.md` must exist |
| How → Exec | Checklist has items | plan.md, checklist.md, and at least one real actions/ACTION_N.md must exist |
| Exec → Done | `outcome.md` written | All checklist items checked |

Hard blocking: hooks exit code 2 on gate failure.

### The gates by name

One line each. On Claude the five edit-path gates (savepoint-pre, lock-gate, code-gate,
links-gate, create-gate) run inside one dispatcher process per Write or Edit, in that fixed
order with the first deny winning; what each gate checks is unchanged.

- **savepoint-pre** appends the savepoint ledger line before a write into an intent dir; it
  records and never denies.
- **lock-gate** admits only the intent's lock owner or a registered delegate to write into an
  active intent directory.
- **code-gate** denies a code edit before How is delivered and a code edit outside the
  provisioned worktree (stage rule or worktree rule, first match wins), with the audited
  `# plastic-ok` escape.
- **links-gate** enforces the derived `## Links` projection contract at write time.
- **create-gate** validates the proposed intent file at What write-time.
- **bash-gate** (on the Bash matcher) intercepts a write attempted through a bash or
  interpreter one-liner, with the same audited escape.
- **gate-check** (PostToolUse) enforces lifecycle stage order after each write.
- **future-intent-check** (UserPromptSubmit) surfaces parked future intents whose keywords
  match the user's message; it informs and never denies.

See `plastic-conventions > references/gates-and-enforcement.md` for the escape and logging
detail.

## Delivery Isolation and the Single-Owner Lock

Exactly one session or agent develops an intent's delivery at a time. Ownership is a
session-keyed, durable `delivery.lock` (O_EXCL) in the intent directory; liveness is a lease
(the owner's hooks refresh the file mtime, stale means older than the TTL). The `/tmp` session
bridge is only a cache: the lock file wins on any disagreement. A per-artifact claim token
arbitrates the file grain underneath the lock. Every code-touching intent gets its own git
worktree (`<repo>/.claude/worktrees/{id}--{slug}`, branch `plastic/{id}--{slug}`); code edits
happen only inside it. On a confirmed solo delivery the lock and worktree gates relax to
advisory; any parallel or team activity restores strict enforcement.

"Intent done" is one law with three signals that must agree: INDEX `## Completed` /
`## Abandoned`, `outcome.md`, and the savepoint `Done` line; INDEX is authoritative on any
conflict.

Structural maintenance (WORK vs MAINTENANCE) never touches delivered content: it only records
itself in `revisions.md`, and only proceeds when the target's `delivery.lock` is not fresh.

See `plastic-conventions > references/locks-and-worktrees.md`,
`references/completion-and-done.md`, and `references/maintenance-and-revisions.md` for the full
doctrine.
