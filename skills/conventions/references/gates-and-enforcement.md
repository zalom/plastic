# Gates and Enforcement

This chapter holds the escape-and-logging depth for each transition gate.

#### The gates by name

Each gate guards one thing. All are hard:

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

