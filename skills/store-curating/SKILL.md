---
name: plastic-store-curating
description: |
  Use when completing or reviewing intents, reorganizing the index,
  or when the intent store needs maintenance. Examples:
  <example>Context: User has finished implementing a feature.
  user: "This intent is done, clean up the index"
  assistant: "I'll use the intent-curator to update the intent status and reorganize INDEX.md"
  <commentary>Intent lifecycle change triggers curator for index maintenance.</commentary></example>
  <example>Context: The intent store has grown and clusters need review.
  user: "Organize the intents"
  assistant: "I'll use the intent-curator to review clusters, flag orphans, and suggest connections"
  <commentary>Periodic maintenance of the Zettelkasten structure.</commentary></example>
user-invocable: false
---

# Intent Curator

Dispatches to the `plastic-intent-curator` agent for intent store maintenance.

## When to Use
- Completing or reviewing intents
- Reorganizing INDEX.md
- Cluster maintenance, orphan detection, link discovery
- Batch status updates

## Workflow

Invoke the `plastic-intent-curator` agent via the Agent tool with `subagent_type: "plastic-intent-curator"`. Pass the user's request as the prompt, including:

1. **What to do** - complete intent, reorganize, triage stale, etc.
2. **Which store** - global (`~/.plastic/`) or project (`.plastic/store/`)
3. **Which intents** - by ID or "all active"

The agent handles:
- Intent lifecycle management (status transitions, Outcome sections)
- INDEX.md maintenance (Active/Future/Clusters/Completed/Abandoned sections)
- Link discovery between related intents
- Cluster management (create, merge, rename)
- Orphan detection

Read `../plastic-conventions/references/knowledge-graph.md` for the linking doctrine: tiers of
influence, sources versus chain, and the `## Links` projection, before judging a link discovery or
orphan finding. This path resolves relative to this skill's own installed directory.

When an intent reaches a terminal state, moved to Completed OR Abandoned, do these things:

1. Author a real `outcome.md` in the intent directory from `~/.plastic/templates/outcome.md`, with the frontmatter `disposition: delivered` for a completed intent or `disposition: abandoned` for an abandoned one. `outcome.md` is MANDATORY at every terminal, delivered and abandoned alike: on abandon it records the abandonment reason and replaces the scaffolded placeholder sentinel (never leave `outcome.md` a placeholder at a terminal).
2. Call `plastic-intent-ending` for the terminal-transition close (INDEX move, savepoint `Done` bookend, store commit, disarm, and the QMD reindex last): `ruby ~/.plastic/scripts/end-intent --store <store> --id <id> --disposition delivered|abandoned`, then follow that skill's own disarm and reindex steps. Never restate those one-liners here.

After the agent completes, report what changed.

## Maintenance dispatch (intent 197)

When invoked to fix a structural finding on an intent OTHER than one currently being delivered
(for example, from `/plastic-doctor`'s fix-all routing), the `plastic-intent-curator` agent
follows its own step 7: it detects (never acquires) the target's delivery lock, requires a
clean working tree, and performs the fix on a fresh branch merged back to main as one closed
operation, with an append-only `revisions.md` receipt in the same pass as the edit. See
`agents/plastic-intent-curator.md` for the exact mechanics.

Read `../plastic-conventions/references/maintenance-and-revisions.md` for WORK versus
MAINTENANCE, the `revisions.md` move-and-record contract, and the violation-tag catalog before
running a maintenance dispatch like this one.
