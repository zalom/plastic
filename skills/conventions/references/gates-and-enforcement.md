# Gates and Enforcement

This chapter holds the retrieval-gate mechanics and the escape-and-logging depth for each transition gate.

#### Retrieval Gate

Advisory. Hard gates guard writes, locks, and structure, never reads or searches. Read,
Grep, Glob, and bash search are always allowed, including over the stores. When QMD is
present and fresh, a content search over store markdown receives an advisory hint pointing
at `qmd search` alongside its result; when QMD is present but stale, a background reindex
fires so the next turn's hint runs against a fresh index (never synchronous). QMD, Enola,
and Serena are recommendations, not obligations: the UserPromptSubmit power-tools hook
appends one recommendation line per present tool, naming Enola only, not both, when Enola
and Serena are both present (Enola-first, one code-navigation slot). The legacy trailing `# qmd-ok` token is still
accepted on Bash commands and simply silences the hint. Scope stays the agent's own tool
calls; Ruby `File.read` inside a script is invisible to the hook by design.

The deterministic entry point is the `scripts/qmd-sync` CLI (verbs: detect, register, reindex,
status, search), a clean no-op when QMD is absent. Each store indexes into its own
`plastic-<slug>` collection (`plastic-global` for the global store, `plastic-<slug>` per project).
Index mutation is lifecycle-only, and the reindex runs LAST in the End tail, after the bridge
purge. See `docs/internals.md` for depth.

#### The gates by name

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
  `~/.plastic/.cache/gate-escapes.log`. The code gate (Write and Edit) carries the identical
  audited `# plastic-ok` escape, logged to the same file. The escape does not extend to
  `NotebookEdit` or MCP structural edits: they are still gated, just without an escape hatch.
- **retrieval-gate** is advisory only (see the Retrieval Gate section above): it hints at QMD and
  never blocks a read or search.

