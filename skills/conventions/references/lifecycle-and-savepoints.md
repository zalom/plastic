# Lifecycle and Savepoints

This chapter holds two things: what an intent records while the work runs versus what is
backfilled when it ends, and how an insight reaches the intent when the writer cannot
write the file itself.

## The live record and the backfilled documents

While working, an intent records four things, and only these are its truth of what
happened:

- the intent file: `## Context` and `### Decisions` (written in Why) and `## Insights`
  (one line per ruling, appended as it happens);
- checklist.md: the items, ticked as they are actually performed;
- savepoint.md: the append-only stage ledger, written by the hooks and the scripts;
- the commits on the intent's branch.

The four judgment documents (spec.md, plan.md, actions/, outcome.md) are written when
there is something to say. In thinking mode an agent writes them during Why and How. In
direct mode they usually stay as the scaffold placeholder until the close, and
`scripts/end-intent` then backfills each one still missing or still a placeholder from
the live record (intent 308): `## Problem` from `## Intent`, `## Decisions` from
`### Decisions`, `## Acceptance Criteria`, `## Steps`, `## Items`, `## Delivered`, and
`## Follow-ups` from the checklist, `## Notes` from `## Insights`, `## Verification` from
the diff on the intent's own worktree, and outcome.md's `disposition:` from the close.
Every other section keeps the template's stub text; nothing is invented. A backfilled
file carries a marker comment on the line after its title, and the savepoint gains one
`Exec  backfilled <list>` line. A file with hand-written content, even under a leftover
sentinel line, is never touched. The same writer is exposed as `scaffold-intent backfill`
for the doctor fix hint `backfilled_complete`.

The close never refuses for a document it can write itself. Doctor's per-intent structure
check runs after the backfill as a report: an unchecked box, a malformed intent file, or
a wrong-disposition outcome.md is named on stderr, the close proceeds, and
`/plastic-doctor --intent <id>` keeps reporting it until fixed.

## Insights from a writer that cannot write the file

Background sessions and dispatched sub-agents do not write the insight themselves. They carry
each nugget home in the completion report's `insights:` field, and the orchestrator (or any
agent that can write the file) persists it via the helper. A session that cannot write the
intent file still returns its report, so the insight survives.

For the stage table (What/Why/How/Exec, deliverable, owning skill), see PLASTIC.md's Lifecycle
Stages section; each named skill's own `references/` holds that stage's own depth.
