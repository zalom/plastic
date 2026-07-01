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
    revisions.md          # optional - append-only structural-maintenance audit trail
```

Lifecycle files (`spec.md`, `plan.md`, `checklist.md`, `outcome.md`) have defined
roles. Supporting artifacts that aren't lifecycle deliverables — research reports,
reference docs, external API snapshots, screenshots, diagrams — go in `resources/`.
Name files inside as `{type}--{description}.md` (e.g., `deep-research--gsd-core.md`).

`revisions.md` is an optional, append-only structural-maintenance audit trail. It is not a
lifecycle deliverable and is never scaffolded at intent birth. Its mere existence signals that
the intent underwent structural (not conceptual) change. Structural maintenance is move-and-record:
it removes a misplaced section, file, or ref from its artifact and preserves that content in full
inside `revisions.md` (newest entry at the bottom, one entry per relocated item), so no record is
lost and the delivered meaning is never altered. Changing what an intent delivered is a new intent,
not a revision.

### Structural maintenance and revisions.md

When a delivered intent accumulates structural junk (an unsanctioned section, a stray file, a
frontmatter edge to an intent that no longer exists), the intent-curator relocates it into
`revisions.md` instead of reopening the work. Each entry is a versioned, dated header
(`## Revision vN - YYYY-MM-DD-HH:MM`) plus `Why` (one sentence naming the broken rule, ending
with `[rule: <tag>]`), `Prior location`, and either `Content held` (the verbatim removed
content) or, for a frontmatter edit, a one-line `Change` (before and after). A stray file has
its full content embedded and the original is deleted.

Violation tags (starter set, free-text tags allowed):
- `unsanctioned-section`: a top-level section the sanctioned-section rule now rejects
- `phantom-section`: a section referenced but not present or not sanctioned
- `stray-file`: a file that does not belong in the intent directory
- `dangling-ref`: a link or reference to something that no longer exists
- `broken-chain`: a chain frontmatter edge to an intent that no longer exists
- `broken-source`: a sources frontmatter edge to an intent that no longer exists
- `misplaced-content`: content that belongs in a different artifact or section

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

One-line entry convention. Each index entry is ONE line: `- [<id> <terse title>](<dir>) <tags>`.
The title is the title, not a summary: aim for about 80 characters, no multi-sentence
descriptions. This is a self-check, not a gate.

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

A single capability-aware PreToolUse gate enforces retrieval-first routing on the agent's own
Bash/Read/Grep/Glob calls (and on subagents, since PreToolUse binds them). The gate is
OPERATION-based: it separates searching from reading, and it never stands between you and
reading something you have already located.

- Only CONTENT SEARCH over a Plastic store is gated. The Grep tool and bash `grep`/`rg`/`ag`
  whose target is at or under a store route to QMD when QMD is present and the index is fresh:
  the raw scan is blocked and you use `qmd search`/`qmd query` (or `scripts/qmd-sync search`)
  instead. When QMD is present but stale, the search is allowed this turn and a background
  reindex is fired so the next turn enforces against a fresh index; reindex is never
  synchronous. When QMD is absent, the search is allowed.
- Reading a known target (the Read tool, bash `cat`/`head`/`tail`) and structural discovery
  (the Glob tool, bash `find`/`ls`) are always allowed, including over the store. QMD cannot
  list directories or hand back one specific file, so these are never gated.
- Code is never hard-gated here. Symbolic code navigation via Serena is a soft prompt mandate
  (the UserPromptSubmit power-tools hook), not a block: content grep over code is allowed,
  because Serena navigates symbols and cannot grep arbitrary strings.
- QMD failure model. Absent or stale degrades to allow (stale also fires the background
  reindex). A broken QMD, where the freshness probe errors or times out, also fails open, and
  the hook emits a one-line warning so a degraded QMD is visible rather than silent.
- Bypass: append a trailing `# qmd-ok` shell comment to a Bash command when you attempted
  discovery and it did not serve you (no hits, or results that do not answer your need by your
  reading of the snippets, not their score). A quoted or echoed occurrence does not bypass.
  Bypasses are logged. The gate enforces that discovery was attempted, never that it succeeded.
- Scope: only the agent's tool calls. Ruby `File.read` inside a script is invisible to the gate
  and is out of scope by design.

## Context-economy measurement buckets (84a)

Intent 84 defines three buckets for sibling 84a to audit against; 84 does not run the audit.

- (a) gate-hook prose tokens: the per-transition narration emitted by the gate hook.
- (b) main-loop store-read tokens: tokens the main agent spends reading or grepping the store
  in the transcript.
- (c) authored-section sizes: sizes of authored artifacts (INDEX entries and the like).

## Transition Gates

| Transition | Trigger | Gate |
|---|---|---|
| What → Why | `spec.md` written | — |
| Why → How | `plan.md` + `actions/` + `checklist.md` | `spec.md` must exist |
| How → Exec | Checklist has items | Plan triplet must exist |
| Exec → Done | `outcome.md` written | All checklist items checked |

Hard blocking — hooks exit code 2 on gate failure.

## Delivery Isolation and the Single-Owner Lock

Exactly one session or agent develops an intent's delivery at a time. Ownership is the armed
session bridge, which doubles as the delivery lock: arming records the owning session, the
owner pid, an acquired-at timestamp, and the host. Another session that finds an armed bridge
for the same intent with a live owner backs off; if the owner pid is dead the lock is
reclaimable. This is mandatory, not a convention.

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
| Authoring skills, agents, hooks | `plastic-creating-skills` | progressive disclosure, agentskills.io spec |
| Evaluating skills, evals | `plastic-evaluating-skills` | eval methodology, convention checks |
