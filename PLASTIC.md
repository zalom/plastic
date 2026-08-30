# Plastic: Conventions

> **This file is maintained by Plastic.** It is overwritten on update; do not edit it. Project
> rules go in `AGENTS.md`. Deeper doctrine lives in the six `plastic-conventions` chapters
> (`references/<chapter>.md`: knowledge-graph, lifecycle-and-savepoints, locks-and-worktrees,
> completion-and-done, maintenance-and-revisions, roadmaps), read on demand.

## Two Modes, Plus Auto

| Mode | "How to execute" comes from | Who runs it |
|---|---|---|
| **Direct** (default) | the prompt; at most one clarifying question | this session, inline; record after |
| **Thinking** | a conversation: each ruling an insight, then the action files | this session, then as in direct |
| **Auto** | a registered intent with a clear prompt | a background team under a lock and a worktree |

There are no tiers: there is only work. The Coordinator loop (build, observe, repeat) wraps
every intent: an intent's `## Insights` feed the observe phase.

## What is an Intent

A directory in the store holding `{ID}--{slug}.md` and its record: a desire someone wants to
accomplish, explore, or understand. The unit of work is always an intent, never a ticket. The
day ledger is one too: the session intent, one per calendar day, that direct work records into.

```
store/ID--three-to-five-words/
  {ID}--{slug}.md   # required: Intent, Context, Outcome, Insights, Links sections
  checklist.md      # while working: one item per executed request
  savepoint.md      # while working: one line per milestone, append-only
  spec.md           # backfilled at intent end: requests and decisions
  plan.md           # backfilled: what was thought
  actions/          # backfilled: how it was done (at least one ACTION_N.md)
  outcome.md        # backfilled: what changed; mandatory at Completed and Abandoned
  resources/        # {type}--{description}.md
  revisions.md      # optional: append-only maintenance audit trail
```

Frontmatter is identity and knowledge graph only, nothing operational: `id`, `intent`,
`sources` (direct ascendants, loaded strongly), `chain` (what it spawned, traversed lightly),
`created`, `author` (`human` or an agent name), `tags`. Only the day ledger adds `mode: direct`.
IDs follow Luhmann's alternating convention (`1`, `1a`, `1a1`, `1a1a`); siblings increment
(`1a`, `1b`).

## The Record: Stages as its Shape

| Stage | Section | Deliverable | Skill |
|---|---|---|---|
| **What** | `## Intent` | `{ID}--{slug}.md` | `plastic-intent-creating` |
| **Why** | `## Context` + Decisions | `spec.md` | `plastic-intent-speccing` (thinking mode) |
| **How** | `checklist.md` + `actions/` | `plan.md` | `plastic-intent-speccing` writes the action files |
| **Exec** | `## Outcome` | `outcome.md` | `plastic-intent-executing`; `plastic-intent-ending` closes |

Stages are the shape of the record, not checkpoints: nothing blocks a write. Only "how to
execute" (a checklist item plus its action) must exist before work; the rest is backfilled at
intent end from what was recorded while working.

Invoke a skill for your harness: Claude Code uses the slash form (`/plastic-intent-creating`);
Codex CLI uses a dollar prefix instead (`$plastic-intent-creating`), and may also select a skill
implicitly by matching its description.

`## Insights` is the append-only log of durable discoveries from every stage, newest at the
bottom, never prepended, each entry prefixed `{utc-iso8601} · {stage} · {author}`. Write
through `scripts/insight-append <intent_dir> <text> --stage S --author A`, which ships with
every install and update, formats the prefix, validates it, and appends at the bottom.

## Agents and Skills

An auto team is `plastic-enforcer` (the lead) plus `plastic-executor`; models live in
`agents.models.<harness>.<agent>`.

Twenty skills, each `plastic-<name>`, listed by your harness. `plastic-doctor` checks
installation health (core, store, and full scopes). `plastic-feedback` turns a Plastic quirk,
bug, or feature idea into a redacted local report and a prefilled GitHub issue URL; only the
user submits it. If the user hits one, offer to invoke the plastic-feedback skill yourself
instead of waiting to be asked. A release is a collection of intents; `plastic-releasing`
runs the flow. A roadmap is an ordered, delivery-side collection; `plastic-roadmap` owns it.

## State System

```
~/.plastic/                    # Global store (git, never pushed)
  INDEX.md                     # Structure note
  config.yml, projects.yml     # Preferences; slug -> path
  store/ID--slug/              # Strategic intents
  store/.sessions/<YYYYMMDD>/  # Day ledger: <YYYYMMDD>.md, checklist.md, savepoint.md
  store/.tmp/<session>/        # current (the pointer), heartbeat; git-ignored
~/.plastic/projects/{slug}/    # Project store: INDEX.md, AGENTS.md, roadmaps/, store/
```

`<session>` is the first eight characters of the session id. The pointer holds a day id (the
day ledger takes the record) or an intent id (an auto team owns the record); session start
writes today's day id. The SessionStart hook picks the project store by matching the working
directory against `projects.yml`; no Plastic files land in project code.

Naming: intents are `ID--three-to-five-words`, the file matching the directory
(`1a1--slug/1a1--slug.md`); next id: `ruby ~/.plastic/scripts/folgezettel-id <parent_id>
<store_path>`. Day ledgers are digits only (`20260828`), never hyphenated, never flattened to
the store root, so the id allocator and every 1.x store walker skip them.

`INDEX.md` is a Zettelkasten structure note, not a table of contents. Sections: `## Active`,
`## Future`, `## Clusters`, `## Abandoned`, `## Completed`. One line per entry,
`- [<id> <terse title>](<dir>) <tags>`, about 80 characters: a title, not a summary.

## Rules for Skills

1. Work records into an intent: the day ledger by default, a registered intent when the
   pointer names one. Researches are intents too; no separate folder.
2. Artifacts go in the intent directory, never in `docs/plans/` or `docs/specs/`: code goes in
   the project, everything else in the intent. Capture observations in `## Insights`; at the
   end write `outcome.md` and `## Outcome`, and update INDEX.md.
3. State is derived from what exists: `outcome.md` present means done, so never write it
   before the checklist is fully checked. Status lives on checklist items, not intents.
4. The global store is never pushed (`~/.plastic/` holds sensitive data); agent-created repos
   are private by default (`gh repo create --private`).
5. Intents are created only via `plastic-intent-creating`, never hand-authored. It
   self-verifies with `scripts/validate-intent`, so every intent is born complete; `--intent`
   text is escaped for double quotes and backslashes before it lands in frontmatter, and a
   reciprocal `chain:` append preserves the target intent's existing flow- or block-style
   entries.

## House Style (self-check)

Answer or decision first; bullets over paragraphs; no preamble, no end-recap; one
question-cluster at a time; reasoning stays in the thinking channel. Tables are the default
for discovery deposits, research reports, and agent reports, and required for any listing of
intents or multi-factor comparison.

## QMD, Enola, and Serena

Recommendations, not obligations, and only when present. QMD: prefer `qmd search` /
`qmd query` over the `plastic-*` collections to check for existing or related intents before
treating work as new. Enola, or Serena when Enola is absent: prefer its symbol resolution (or
`.enola/facts.jsonl`) for code navigation over grep.

## Auto Teams: the Lock and the Worktree

Locks and worktrees exist only for auto teams. One team develops an intent at a time: a
session-keyed `delivery.lock` in the intent directory, alive while its mtime lease is fresh.
Code edits happen in the intent's worktree (`<repo>/.claude/worktrees/{id}--{slug}`, branch
`plastic/{id}--{slug}`). "Done" is three signals that agree: INDEX `## Completed` or
`## Abandoned`, `outcome.md`, and the savepoint `Done` line; INDEX wins on conflict.
