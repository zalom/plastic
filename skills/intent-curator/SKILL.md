---
name: plastic-intent-curator
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

1. **What to do** — complete intent, reorganize, triage stale, etc.
2. **Which store** — global (`~/.plastic/`) or project (`.plastic/store/`)
3. **Which intents** — by ID or "all active"

The agent handles:
- Intent lifecycle management (status transitions, Outcome sections)
- INDEX.md maintenance (Active/Future/Clusters/Completed/Abandoned sections)
- Link discovery between related intents
- Cluster management (create, merge, rename)
- Orphan detection

When an intent reaches a terminal state — moved to Completed OR Abandoned — do these things as the closing act of the transfer, in the canonical End-tail order (see PLASTIC.md `## Delivery Isolation and the Single-Owner Lock`):

1. Author a real `outcome.md` in the intent directory from `~/.plastic/templates/outcome.md`, with the frontmatter `disposition: delivered` for a completed intent or `disposition: abandoned` for an abandoned one. `outcome.md` is MANDATORY at every terminal, delivered and abandoned alike: on abandon it records the abandonment reason and replaces the scaffolded placeholder sentinel (never leave `outcome.md` a placeholder at a terminal).
2. Stamp the terminal savepoint bookend (intent 81), so the ledger's last line records the disposition: `ruby -r ~/.plastic/scripts/lib/bridge -e 'Bridge.append_terminal_savepoint("<intent_dir>", "delivered")'` (use `"abandoned"` for an abandoned intent). Idempotent.
3. Refresh the QMD index for the affected store LAST, after the terminal move and savepoint (no-op when QMD absent), running in the background so it never blocks: `ruby ~/.plastic/scripts/qmd-sync reindex --store <store-root> --async`.

After the agent completes, report what changed.
