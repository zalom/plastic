# Plastic: Conventions

> **This file is maintained by Plastic.** It will be overwritten when the
> plugin is updated. Do not modify it: your changes will be lost.
> For project-specific rules, use `AGENTS.md` instead.

See `PLASTIC-reference.md` for reference material: read it on demand, it is not injected at session start.

## What is an Intent

A directory in the store containing `{ID}--{slug}.md` and optional supporting files.
It represents a desire: something a human or agent wants to accomplish, explore, or understand.

```
store/
  ID--three-to-five-words/
    {ID}--{slug}.md       # required - the intent itself
    spec.md               # optional - specification (Why deliverable)
    plan.md               # optional - implementation plan (How deliverable)
    checklist.md          # optional - execution registry (How deliverable)
    outcome.md            # optional - detailed result (Exec deliverable)
    actions/              # optional - individual work items
    resources/            # optional - research, references, screenshots, diagrams
    savepoint.md          # optional - deterministic cycle-step ledger (auto-written)
    revisions.md          # optional - append-only structural-maintenance audit trail
```

Lifecycle files (`spec.md`, `plan.md`, `checklist.md`, `outcome.md`) have defined
roles. Supporting artifacts that aren't lifecycle deliverables (research reports,
reference docs, external API snapshots, screenshots, diagrams) go in `resources/`.
Name files inside as `{type}--{description}.md` (e.g., `deep-research--gsd-core.md`).

`revisions.md` is an optional, append-only structural-maintenance audit trail. It is not a
lifecycle deliverable and is never scaffolded at intent birth. Its mere existence signals that
the intent underwent structural (not conceptual) change. Structural maintenance is move-and-record:
it removes a misplaced section, file, or ref from its artifact and preserves that content in full
inside `revisions.md` (newest entry at the bottom, one entry per relocated item), so no record is
lost and the delivered meaning is never altered. Changing what an intent delivered is a new intent,
not a revision.

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
- `## Links` is a DERIVED view, not a place to author links (Convention over Configuration).
  It equals the projection of `sources` (first) then `chain`. Never hand-write or hand-edit a
  `## Links` line, and never auto-delete one. The edge lives in the frontmatter graph; the
  section is regenerated from it (doctor `graph_links_projection` enforces this identity). To
  add a link, add the frontmatter edge, then reproject.
- Links are decided by CONTEXT INFLUENCE, not by shared files, shared symbols, or a topic
  similarity score. The question is whether one intent's context actually informed another.
  Three tiers:
  - **sources:** the foundational context that shaped this intent's creation (a split, an idea
    born during development, a merge). Earns an edge.
  - **chain:** the context that materially helps DELIVER this intent. This is a HIGH bar: only
    the genuinely delivery-moving intents, not everything in the same area. Earns an edge,
    reflected in `## Links`.
  - **tags:** a loose theme grouping for search. NOT a link. A shared tag is a door INTO the
    store (filtered discovery), not a pathway BETWEEN two notes.
  Judging influence is an agent's call, made by reading the candidate's Intent and Context. A
  script cannot grade it, so `scripts/link-suggest` only gathers candidates with that evidence,
  records a confirmed edge with a rating and reason, and flags drift.
- IDs use Luhmann's alternating convention: `1` → `1a` → `1a1` → `1a1a`
- Multiple branches increment: `1a`, `1b`, `1c`

## Lifecycle Stages

| Stage | Section | Deliverable | Detail |
|-------|---------|-------------|--------|
| **What** | `## Intent` | `{ID}--{slug}.md` | `plastic-creating-intent` |
| **Why** | `## Context` + Decisions | `spec.md` | `plastic-brainstorming` |
| **How** | Planning | `plan.md` + `actions/` + `checklist.md` | `plastic-writing-plans` |
| **Exec** | Execution | `outcome.md` | `plastic-executing-plan` |

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
(`scripts/insight-append <intent_dir> <text> --stage S --author A`), which formats the prefix,
validates it, and appends at the bottom. Hand-editing `## Insights` is an escape hatch; the
helper is the default so the format cannot drift.

Background sessions and dispatched sub-agents do not write the insight themselves. They carry
each nugget home in the completion report's `insights:` field, and the orchestrator (or any
agent that can write the file) persists it via the helper. A session that cannot write the
intent file still returns its report, so the insight survives.
For full lifecycle detail, the skills in the Detail column have references/.

## Tiers (proportional auto sizing)

Auto mode sizes every intent S/M/L at Why: S = single mechanism or file cluster (hours);
M = one subsystem (about a day); L = cross-cutting or novel design.

Speed comes from two levers only: artifact content depth and agent topology. The
same-structure invariant holds: same file set, stage order, gates, and savepoint ledger at
every tier and in both modes.

S/M collapse the topology (one thinker agent writes spec.md then plan.md plus
checklist.md in one context; actions/ only for L; a sonnet executor implements). L keeps
the full team.

Never cut at any tier: the independent reviewer, outcome.md as truth of delivery, the
delivery lock, worktree isolation, intent creation via skill, INDEX as status truth, the
QMD reindex at End.

Tier is recorded as a `Tier: S|M|L` line at the top of spec.md. It is convention-only,
read by the orchestrator, not enforced by any gate or by doctor.

Guided mode is unchanged: full-depth artifacts, the human at every gate.

## Agent Models and Dispatch (intent 116)

Every lifecycle stage has exactly one dispatchable background agent, plus the enforcer that
orchestrates them:

| Stage | Agent |
|---|---|
| What | `plastic-intent-discovery` |
| Why | `plastic-brainstorming` + `plastic-spec-specialist` |
| How | `plastic-planner` |
| Exec | `plastic-executor` |
| Done | `plastic-intent-curator` |

Final-gate code review stays an ad-hoc subagent the enforcer dispatches at the final gate, not
a standing role.

**Auto-mode entry.** `plastic-auto` is the entry skill for autonomous delivery: it takes over How
and Exec, spins up the team above, and works the dashboard's dispatchable queue. The dashboard's
`--data` output splits intents into a `dispatchable_queue` (work an agent can pick up) and
`human_only` (intents that need a person); auto mode consumes the former.

**Model contract.** Every agent in `agents/*.md` pins an explicit Claude Code model alias in
its own frontmatter: `opus`, `sonnet`, or `haiku`. Never `inherit`, never Fable. Aliases track
"latest per tier" so no Plastic release is required to advance a tier. The tier by role:
`plastic-enforcer`, `plastic-brainstorming`, `plastic-planner` are `opus`;
`plastic-spec-specialist`, `plastic-executor`, `plastic-intent-curator`,
`plastic-future-intent-researcher`, `plastic-intent-discovery` are `sonnet`.

**Config and installer mechanism.** `agents.models.<basename>` in a project's
`<dir>/.plastic_store/config.yml` or the global `~/.plastic/config.yml` overrides one agent's
tier. Precedence is project, then global, then the shipped default, matching every other
`read-config` key. The installer applies the resolved override to each agent file's `model:`
line at copy time (install, update, and repair, across every harness target). With no override
configured, the shipped frontmatter passes through unchanged.

**Dispatch-time contract.** Frontmatter is primary, and Claude Code reads it at dispatch, but
because that read is a harness implementation detail rather than a contract Plastic controls,
every dispatch site also resolves the target agent's model through the config chain
(`read-config agents.models.<basename> --project <repo>`) and passes it explicitly at dispatch,
belt-and-braces on top of the frontmatter pin.

**Cross-harness portability.** The dispatch and model-tier contract above is harness-facing. The
adapter layer that maps Plastic's hooks and model aliases onto each supported agent runtime
(Claude, Codex, Hermes) is the cross-harness portability layer; see
docs/reference/harness-adapters.md for the adapter contract.

**Orchestrator advisory.** At auto-mode start, the orchestrator recommends once that the user
run the main session on the best available thinking model (Fable, Opus, or whatever supersedes
them). This is advisory only: it changes no behavior and blocks nothing if ignored, and it
concerns the human's main session, never a dispatched subagent.

**`plastic-intent-discovery`.** The What-stage agent. It fires at intent activation, after the
delivery lock is armed and before Why begins, running under that lock as the owner session (it
does not acquire the lock itself and is not blocked by it): it reads the intent's
`chain`/`sources` frontmatter, runs QMD-first discovery over completed predecessor work and
related parked or future intents, and deposits findings to `resources/discovery--<slug>.md` in
the intent directory ONLY. It never writes the intent file, `spec.md`, or any other lifecycle
deliverable; the Why-stage `plastic-brainstorming` agent reads its deposit and enriches
`## Context`.

`savepoint.md`: a deterministic, append-only ledger of cycle-step milestones (one line per
lifecycle boundary, newest at the bottom), written automatically by the gate hook. It is
sugar on top of the conventions, not a source of truth: state is always derivable from
files-on-disk, and the ledger is rebuildable. It exists so a resuming agent reads the cycle's
succession at a glance (last line = where we are).

## Auto-Mode Human Reporting (intent 92)

In auto mode the orchestrator briefs the human at every lifecycle stage boundary in a fixed,
impact-first shape (the EM-to-CTO report contract): State, then Risk, then Call. It leads with
what changed and why it matters, names one risk, and leaves the decision to the human. Separately,
the `plastic-humanizer` skill cleans authored prose (specs, outcomes, READMEs, release notes) of
AI tells and slop; it is for documents, not for every reply.

## Operational Skills

Beyond the lifecycle agents, Plastic ships thin skills for day-to-day operation:

- **`plastic-dashboard`** renders a deterministic Value x Effort work cockpit across the global
  store and every project, and emits a machine-readable queue (`scripts/dashboard.rb --data
  [continue|project <slug>]`) that auto mode consumes.
- **`plastic-doctor`** checks installation health. See the Skills Reference in PLASTIC-reference.md
  for its three scopes (`--core` for the boot integrity check, `--store` per store on dashboard
  load, and the full no-flag walk after an update).
- **Lifecycle skills** (`plastic-install`, `plastic-update`, `plastic-uninstall`,
  `plastic-versions`, intent 55) are thin wrappers over a single pinned
  `npx -y @zalom/plastic@<channel> <verb>` call: initialize or repair an install, advance a
  channel, remove Plastic, and step the local versions ledger.

## Releases and Versioning

Plastic ships as versioned releases. A release is a collection of intents: a cut bundles whichever
intents landed since the previous cut and completes them, so the intent schema itself stays
release-agnostic and carries no version number. Cutting a release bumps the three version files
(`package.json`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`), tags
`v{version}`, runs `gh release create --latest`, and publishes to npm. The npm dist-tag follows
the version string: a `-alpha` suffix routes to the `alpha` tag, `-beta` to `beta`, and a plain
version with no suffix routes to `latest`. Release history lives in `CHANGELOG.md` at the repo
root, one line per cut. The `plastic-releasing` skill runs the whole flow.

Deprecations are declared in `deprecations.yml` and shown at SessionStart. While Plastic is
pre-1.0, a satisfied deprecation may be removed immediately; from `1.0.0` on the steady-state
grace rule applies (removal at least two minors ahead). See PLASTIC-reference.md for the
Deprecation Process.

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
- Next ID: `"${CLAUDE_PLUGIN_ROOT}/scripts/folgezettel-id" <parent_id> <store_path>`

**Branch vs root: the semantic decision.** The numbering is mechanics; choosing
*whether* to branch is meaning:

- **Branch (`14a`, `14b`):** a sub-task, refinement, or direct continuation of the
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

One-line entry convention. Each index entry is ONE line: `- [<id> <terse title>](<dir>) <tags>`.
The title is the title, not a summary: aim for about 80 characters, no multi-sentence
descriptions. This is a self-check, not a gate.

## Roadmaps

A roadmap is a named, ordered, delivery-side collection of intents (waves of parallel-safe
entries plus an append-only log), the delivery-side counterpart to a release and a sibling of
`INDEX.md` (never inside `store/`). Create, order, close, and consume one with `plastic-roadmap`.
`INDEX.md` stays the single writer of intent status; a roadmap entry mirrors it and yields on any
conflict. See PLASTIC-reference.md for the full Roadmaps format.

## Rules for Skills

ALL work flows through intents.

1. Before starting work, check INDEX.md for active intent. If none, create one.
2. Skill output (spec, plan, checklist) goes in the intent directory.
3. On completion, capture observations in `## Insights`.
4. When done, write `outcome.md` + `## Outcome` summary. Update INDEX.md.
5. Researches are intents. No separate folder.
6. Intents are created only via `plastic-creating-intent`. Never hand-author an intent file. The skill self-verifies the written intent with `scripts/validate-intent` before announcing or committing, so every intent is born complete.

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

## Retrieval Gate

Advisory. Hard gates guard writes, locks, and structure, never reads or searches. Read,
Grep, Glob, and bash search are always allowed, including over the stores. When QMD is
present and fresh, a content search over store markdown receives an advisory hint pointing
at `qmd search` alongside its result; when QMD is present but stale, a background reindex
fires so the next turn's hint runs against a fresh index (never synchronous). QMD and
Serena are recommendations, not obligations: the UserPromptSubmit power-tools hook appends
one recommendation line per present tool. The legacy trailing `# qmd-ok` token is still
accepted on Bash commands and simply silences the hint. Scope stays the agent's own tool
calls; Ruby `File.read` inside a script is invisible to the hook by design.

The deterministic entry point is the `scripts/qmd-sync` CLI (verbs: detect, register, reindex,
status, search), a clean no-op when QMD is absent. Each store indexes into its own
`plastic-<slug>` collection (`plastic-global` for the global store, `plastic-<slug>` per project).
Index mutation is lifecycle-only, and the reindex runs LAST in the End tail, after the bridge
purge. See `docs/internals.md` for depth.

## Transition Gates

| Transition | Trigger | Gate |
|---|---|---|
| What → Why | `spec.md` written | (none) |
| Why → How | `plan.md` + `actions/` + `checklist.md` | `spec.md` must exist |
| How → Exec | Checklist has items | Plan triplet must exist |
| Exec → Done | `outcome.md` written | All checklist items checked |

Hard blocking: hooks exit code 2 on gate failure.

### The gates by name

Each gate guards one thing. All are hard except the retrieval gate:

- **create-gate** validates the proposed intent file at What write-time (Write, Edit, and MCP
  edits), so a malformed or incomplete intent never lands.
- **gate-check** enforces lifecycle stage order (spec.md before plan.md, the plan triplet before
  the checklist, all checklist items before outcome.md).
- **lock-gate** arbitrates ownership and claims: it admits only the intent's lock owner or a
  registered delegate to write into an active intent directory, and every deny names the
  resolving `plastic-lock` command.
- **bash-gate** intercepts a write attempted through a bash or interpreter one-liner (a heredoc, a
  `>` redirect, a `ruby -e` or `python -c` write), so the same rules apply whether an edit goes
  through the Write tool or a shell. A trailing `# plastic-ok` comment is an auditable escape that
  lets a deliberate command through, and every use is logged to
  `~/.plastic/.cache/gate-escapes.log`.
- **retrieval-gate** is advisory only (see the Retrieval Gate section): it hints at QMD and never
  blocks a read or search.

## Delivery Isolation and the Single-Owner Lock

Exactly one session or agent develops an intent's delivery at a time. Ownership is
session-keyed and durable: arming acquires `delivery.lock` inside the intent directory
(atomically, O_EXCL), recording the owner session, the host, the acquired-at time, a
delegates list, and the lock type. Liveness is a lease: the owner's hooks refresh the lock
file's mtime on tool activity, and the lock counts as stale only when that heartbeat is
older than the TTL. No process id is consulted anywhere. The /tmp session bridge is a cache
of this state; on any disagreement, or when the bridge is missing, the lock file wins.
Another session that finds a fresh lock backs off; a stale lock is reclaimed only by
explicit takeover, which replaces the lock and appends an audit line to the intent's
savepoint.md. Subagents spawned by the owner write under the owner's lock once registered
as delegates. Disarm clears the lock; the End tail is ordered: verify, merge and remove
worktrees, clear the lock, and only then is the bridge purge-eligible. Repair is one
idempotent function with two entry points: the `plastic-lock` command (status, fix,
release, reclaim, delegate) and `/plastic-intent-starting`, so boarding self-heals. This is
mandatory, not a convention.

Solo-mode gate defaults (intent 128): on a confirmed positive solo determination
(`Bridge.solo_delivery?`, a single owner working alone with no sign of parallel or team
delivery), the lock and worktree arbitration gates relax from enforced to advisory. The moment
any parallel or team activity appears they return to strictly enforced. This is a real behavior
difference, not just a message change: a solo session is not hard-blocked by these gates, a
shared one still is.

The bridge resolves the current session in a fixed precedence: the stdin `session_id` first, then
the `CLAUDE_CODE_SESSION_ID` environment variable, then a derived key when neither is present. A
bridge is purge-eligible by terminal state, not by age: it is removed only once its intent is no
longer active, never on a timer. See `docs/internals.md` for depth.

The delivery lock arbitrates at the whole-intent grain: it decides who may work
an intent at all. Underneath it, a per-artifact claim token (intent 111)
arbitrates at the file grain: it decides who, among those already holding the
delivery lock, is the one writer for one lifecycle file right now. A write to
`spec.md`, `plan.md`, `checklist.md`, or the intent file must hold both the
delivery lock and that file's claim. Claims live in `.claims/<artifact>.claim`
inside the intent directory, one small JSON file per artifact, scoped strictly
per-intent-per-artifact, never session-global. The claim gate is dormant
(allows) when no claim file exists for an artifact, so ordinary single-owner
work is unaffected; it engages, and denies, only when a second writer tries to
take a fresh claim someone else already holds. A stale or corrupt claim fails
open (the write proceeds, the claim yields) and the condition is surfaced in
`plastic-lock status`, which lists any live claims alongside the delivery
lock. See `plastic-lock claim`/`release-claim` and `docs/internals.md` for the
full mechanism.

Two locks share this schema (the two-lock doctrine): `delivery.lock` (exclusive, one owner
plus delegates) and the future `maintenance.lock` (short TTL, structural move-and-record
only). They are mutually exclusive in either direction; maintenance is allowed at any
lifecycle stage provided no delivery lock is held. Intent 108 ships the delivery lock and
the mutual-exclusion seam; the maintenance lock implementation follows intent 93 in a
chained intent.

Every code-touching intent gets its own git worktree named `{id}--{slug}`, and all code edits
for that intent happen only inside it. Plastic provisions the worktree deterministically: it
resolves the project repo from `projects.yml` and runs `git -C <repo> worktree add`, so
isolation never depends on the current working directory. There are two worktrees per project
intent: a code worktree at `<repo>/.claude/worktrees/{id}--{slug}` (branch `plastic/{id}--{slug}`)
and a store worktree at `<plastic_home>/.worktrees/{id}--{slug}` (branch
`plastic-store/{id}--{slug}`), so lifecycle-doc commits and code commits move as one unit.

Provisioning fails open for intents that touch no project code (pure research or decision
intents in the global store, or a non-git repo): those get the lock only, and the worktree
block stays unprovisioned. The fail-open path is always logged, never silent.

Cleanup is part of Done: the End tail merges the branch, then removes both worktrees. Never leave
an orphaned worktree behind, and clear a stale worktree reference with `git worktree prune`.

### Intent delivery, station by station

How one intent travels from boarding to Done, and what the lock, bridge, and gates do at
each station.

| Station | Delivered artifact | Lock and bridge steps | Pre-stage gate | Post-stage record |
|---|---|---|---|---|
| Start (board) | none (a procedure, not a stage) | `plastic-lock fix` self-heals stale, corrupt, or legacy state; arm acquires `delivery.lock` (O_EXCL, session-keyed), provisions the code worktree, writes the bridge cache | lock-gate denies any write into an active intent dir without this intent's lock; every deny names the resolving command | savepoint confirms the boarding station |
| What (create) | `<id>--<slug>.md`, born complete | no lock yet; no bridge | create-gate validates the proposed intent content (Write, Edit, and MCP edits) | savepoint `What` line; intent listed in INDEX `## Active` |
| Why | `spec.md` | owner writes refresh the lease (lock file mtime heartbeat) | gate-check requires the intent file with `## Intent` before spec.md; lock-gate admits only the owner or a delegate | savepoint `Why started`, `Why spec.md created` |
| How | `plan.md`, `actions/`, `checklist.md` | heartbeat on writes; the code gate stays closed until plan.md plus checklist.md exist | gate-check requires spec.md before plan.md, and plan.md plus actions/ before checklist.md | savepoint `How started`, `How plan.md created`, `How checklist.md created`, `Exec started` |
| Exec | code on the intent branch, checklist checked off | heartbeat; code edits confined to the provisioned worktree; delegates write under the owner's lock; bash, interpreter, and MCP writes gated the same way | code-gate, worktree-gate, bash-gate, lock-gate | checklist boxes; savepoint milestones |
| End (done) | mandatory `outcome.md` (`disposition: delivered\|abandoned`), INDEX moves to Completed or Abandoned | ordered End tail: verify, merge and remove worktrees, disarm clears `delivery.lock`, then the bridge is purge-eligible, and the QMD reindex runs LAST (after purge) | gate-check blocks outcome.md while checklist items are unchecked | savepoint `Done delivered` (or `abandoned`); takeover audits, if any, remain in savepoint.md |
| Maintenance (any stage) | `revisions.md` move-and-record entries | future `maintenance.lock` (short TTL), mutually exclusive with `delivery.lock` in either direction; 108 ships the schema seam only, the implementation follows intent 93 in a chained intent | acquisition refuses while the other lock type is fresh; a terminal intent with no lock held is read-only | dated, rule-tagged `revisions.md` entry; savepoint untouched |

### What "intent done" means (intent 93)

Done is one law with three signals, and they must agree. INDEX `## Completed` /
`## Abandoned` is the single canonical terminal marker: it is the store-wide ledger a fresh
session reads first, so it wins on any conflict. `outcome.md` is the "deliverable exists"
signal, and the savepoint `Done delivered|abandoned` line is the audit echo. All three must
agree; when they disagree, INDEX is authoritative and `doctor` flags the mismatch (the
`done_signals` check: `outcome.md` real but still under `## Active`, or terminal without a
real `outcome.md`, or a terminal intent whose savepoint carries no `Done` line).

`outcome.md` is mandatory at every terminal transition, delivered and abandoned alike. It
self-declares its disposition through a `disposition: delivered|abandoned` frontmatter
header. The delivered path authors it with the result; the abandoned path authors it with
the abandonment reason and no longer leaves the scaffolded placeholder sentinel in place.

The canonical End tail runs in this order, and the QMD reindex is always LAST, after the
purge: `outcome.md -> INDEX terminal -> savepoint Done -> commit -> disarm (Worktree.release
-> Lock.release -> purge) -> QMD reindex`. Running the reindex last keeps the index from
ever referencing a bridge or lock that disarm is about to remove.

The post-done access window is lock-bounded: `[INDEX terminal -> Lock.release]`. Through it
the completing session keeps full read and write access to the terminal directory and no
purge can fire (108's lock-held keep-guard keeps the bridge while `delivery.lock` exists).
Once the lock is released the window closes: the bridge becomes purge-eligible and the
directory is frozen. A crash mid-tail is recovered by stale-lock reclaim plus finishing the
tail; `doctor` surfaces this as a "stalled completion" (terminal in INDEX but the lock is
still present or stale). Finishing the tail is FINISHING a completion, never a reactivation:
a done intent is never moved back to `## Active`.

Terminal immutability (the contract intent 112 enforces): a terminal directory is writable
ONLY while a lock is held. The delivery lock covers the completing session's End tail up to
`Lock.release`; the maintenance lock covers sanctioned structural move-and-record edits
after. Terminal with no lock held is frozen. There are only two locks in the system,
delivery and maintenance (108 D11). This governs WRITES only: reads of a terminal intent are
always allowed and unbounded (curator reindex, dashboards, and future intents that reference
its id or chain), so a done intent stays fully readable forever. Intent 93 states this rule;
intent 112 builds the gate that enforces it.

Fail-safe lock doctrine (the contract intent 111 implements): the lock system never traps a
session or burns credits. When a gate cannot verify lock integrity it fails open, degrading
to advisory (warn) rather than hard-blocking. Repair is orchestrator-driven: on a lock-issue
signal the orchestrator inspects and repairs the lock automatically, and the human
`plastic-lock` command is a fallback path, not the trigger. Intent 93 states this doctrine;
intent 111 builds the fail-open behavior, the lock-liveness surface, the lock-issue message,
and the auto-repair.

Scope split. Intent 93 ships doctrine plus the low-risk reconciliation that needs no new
lock: the canonical done-marker and three-signal reconciliation, the mandatory `outcome.md`
plus `disposition` header at both terminals, the End tail with the reindex moved last, the
`done_signals` doctor check (three-signal agreement plus stalled-completion detection), and
the lock-bounded post-done window with its keep-guard test. Intent 111 owns the lock
liveness surface, the lock-issue message, orchestrator auto-repair, and the fail-open
behavior itself. Intent 112 owns the maintenance lock and the immutability gate (it inherits
fail-open from 111). Intent 4a1b1 owns deep agent stuck-detection and is not superseded.

