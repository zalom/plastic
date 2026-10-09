# Lifecycle and Savepoints

This chapter holds two things: what an intent records while the work runs versus what is
backfilled when it ends, and how an insight reaches the intent when the writer cannot
write the file itself.

## The live record and the backfilled documents

While working, an intent records four things, and only these are its truth of what
happened:

- the intent file: `## Context` and `### Decisions` (written in Why) and `## Insights`
  (one line per ruling, appended as it happens);
- graph.json: the nodes, each marked done as it is actually performed;
- savepoint.md: the append-only stage ledger, written by the hooks and the scripts;
- the commits on the intent's branch.

The judgment documents (spec.md, actions/, outcome.md) are written when there is
something to say. An agent writes them during Why and How; the `plastic intent` Next row asks
for `spec.md`, then the work graph, before it points at execution. `plastic intent end` writes
none of them. It prints what is missing, and the agent writes it. `plastic intent show <id>`
keeps reporting a malformed intent file or a wrong-disposition outcome.md until it is fixed.

## Insights from a writer that cannot write the file

Background sessions and dispatched sub-agents do not write the insight themselves. They carry
each nugget home in the completion report's `insights:` field, and the orchestrator (or any
agent that can write the file) persists it via the helper. A session that cannot write the
intent file still returns its report, so the insight survives.

The stages map to commands: What is `plastic intent new`, Why is `plastic intent spec` and
`plastic intent rule`, How is the spec and the work graph the agent writes,
and Exec is `plastic next`, `plastic node done` and `plastic intent end`.
`plastic help tutorial` walks all of them once.
