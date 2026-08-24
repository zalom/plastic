---
name: plastic-conventions
description: >
  Chapters of Plastic doctrine used by more than one skill: the knowledge graph,
  lifecycle and savepoints, tiers and dispatch, gates and enforcement, locks and
  worktrees, completion, maintenance, and roadmaps. Read a chapter when its trigger
  applies to the work in front of you.
user-invocable: false
---

# Plastic Conventions

The chapters below hold Plastic doctrine that more than one skill needs. Core always-on
conventions stay in `~/.plastic/PLASTIC.md`, which is injected at session start. Read a chapter
when the trigger in the second column applies to the work in front of you.

| Chapter | Read it when |
|---|---|
| `references/knowledge-graph.md` | when creating, linking, curating, or indexing intents and you need the sources-vs-chain doctrine, the tiers of influence, the `## Links` projection, or branch-vs-root directory semantics |
| `references/lifecycle-and-savepoints.md` | when running a lifecycle stage or a savepoint and you need the subagent report-home contract for how an insight reaches the intent |
| `references/tiers-and-dispatch.md` | when sizing an intent, choosing agent models, routing to the advisor, or writing an auto-mode human report |
| `references/gates-and-enforcement.md` | when a transition gate blocks you, or before using an audited escape, for the gate mechanics and the logging contract, or when naming, registering, or retiring a hook or skill |
| `references/locks-and-worktrees.md` | before taking or releasing a delivery lock, and when working with claims, worktrees, solo mode, or the station ledger |
| `references/completion-and-done.md` | when ending an intent, for what "intent done" means and the End-stage tail |
| `references/maintenance-and-revisions.md` | before any structural maintenance edit, for WORK vs MAINTENANCE, the `revisions.md` move-and-record contract, the violation-tag catalog, and the context-economy measurement buckets |
| `references/roadmaps.md` | when creating, ordering, closing, or consuming a roadmap, for the file format and the status-mirror rule |

Other skills read these chapters directly at
`../plastic-conventions/references/<chapter>.md`, resolved relative to their own installed
directory. All three harnesses install skills flat into one shared skills root through the same
`install_skills_flat` call, so that path is harness-independent.
