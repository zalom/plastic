# Gates and Enforcement

This chapter holds the escape-and-logging depth for each transition gate.

#### Hook and skill naming and ownership

The `plastic-` prefix is reserved for both surfaces: hooks `HookRegistry` registers and skills
Plastic ships. A user-owned hook or skill must never take it: the installer purges Plastic's
registrations from the agent's hook config on every update, matching by registry launcher name
(current plus `RETIRED_HOOK_NAMES`), and doctor reports every violation it can find. On disk,
`hooks_no_orphans` reports an unregistered `plastic-*` launcher file the registry does not know.
In the live config, `hooks_entries_owned` (Claude) and `codex_hooks_entries_owned` (Codex)
report a config entry that is neither a current registration nor recognizably ours, and,
separately, a current registration whose launcher file is missing from disk. For skills,
`stray_skills` reports a `plastic-*` skill directory the manifest does not track. Renaming or
removing a hook from `events` means adding its old name to `RETIRED_HOOK_NAMES` in the same
change, or every existing install keeps a dead registration.

#### The gates by name

Each gate guards one thing. `scripts/lib/hook_registry.rb` is the single source of truth for
registration. On the edit path (Write, Edit, NotebookEdit, and MCP structural edits) five
gates run inside one dispatcher process per write, in this fixed order with the first deny
winning:

- **savepoint-pre** appends the `started` savepoint ledger line before a write into an intent
  directory; it records and never denies.
- **lock-gate** arbitrates ownership and claims: it admits only the intent's lock owner or a
  registered delegate to write into an active intent directory, and every deny names the
  resolving `plastic-lock` command.
- **code-gate** denies a code edit before How is delivered and a code edit outside the
  provisioned worktree (stage rule or worktree rule, first match wins). It carries the audited
  `# plastic-ok` escape described under bash-gate.
- **links-gate** is the write-time belt for the `## Links` contract: hand-written links lines
  that do not project from the `sources`/`chain` frontmatter are denied.
- **create-gate** validates the proposed intent file at What write-time (Write, Edit, and MCP
  edits), so a malformed or incomplete intent never lands.

Alongside the edit-path dispatcher the registry defines:

- **bash-gate** (on the Bash matcher) intercepts a write attempted through a bash or interpreter
  one-liner (a heredoc, a `>` redirect, a `ruby -e` or `python -c` write), so the same rules
  apply whether an edit goes through the Write tool or a shell. A trailing `# plastic-ok`
  comment is an auditable escape that lets a deliberate command through, and every use is
  logged to `~/.plastic/.cache/gate-escapes.log`. The code gate (Write and Edit) carries the
  identical audited `# plastic-ok` escape, logged to the same file. The escape does not extend
  to `NotebookEdit` or MCP structural edits: they are still gated, just without an escape hatch.
- **gate-check** (PostToolUse on Write and Edit) enforces lifecycle stage order (spec.md before
  plan.md, the plan triplet before the checklist, all checklist items before outcome.md).
- **future-intent-check** (UserPromptSubmit) surfaces parked future intents whose keywords match
  the user's message; like the other prompt-time hooks (continue, auto-arm, power-tools) it
  informs and never denies.

