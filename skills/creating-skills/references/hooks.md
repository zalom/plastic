# Authoring a Lifecycle Hook

A hook is a harness: deterministic code the Claude Code runtime fires at a lifecycle
event. Author one when a probabilistic skill keeps dropping a behavior and that behavior
must hold every time.

For body voice, budgets, and reference rules, see `progressive-disclosure.md` and `skills.md`.
For deciding script versus prose and writing the handler logic, read `scripts.md` when the
handler grows past a few lines. This file covers only hook authoring.

## Contents

- When to reach for a hook (E1)
- The event to matcher to handler model (E2)
- Which event for which job (E2)
- Path rules and executability (E3)
- No-op by default, opt-in (E4)
- Exit codes and output channels (E5)
- Verify the harness engaged (E6)
- Authoring checklist

## When to reach for a hook (E1)

Reach for a hook only after a skill has lost the behavior. The documented order is: first
strengthen the skill description and instructions so the model keeps preferring the skill;
if it still drops the step, enforce it deterministically with a hook. [E1]

Test: ask "does this behavior have to hold even when the model forgets the skill?" If yes
(a gate before a destructive tool, a savepoint before compaction, a format pass after every
edit), the runtime must enforce it, not the prompt. If no, leave it in the skill body and
spend no hook tokens on it. [E1]

A hook is code on the critical path of an event. It is not loaded into context, so it costs
no tokens at trigger time, but a mistuned hook blocks real work. Make it earn the
intervention. [E1]

## The event to matcher to handler model (E2)

Hooks are configured in three nested levels: event, then matcher group, then handler list.
[E2]

- Event: the lifecycle moment (for example PreToolUse, SessionStart, PreCompact).
- Matcher: which instances of that event fire the handler. For tool events the matcher is a
  tool-name pattern (`Bash`, `Edit|Write`, `mcp__memory__.*`). For SessionStart the matcher
  is a source (`startup`, `resume`, `clear`, `compact`). For PreCompact it is `manual` or
  `auto`.
- Handler: what runs. Handler types include `command` (a script, JSON arrives on stdin),
  `http`, `mcp_tool`, `prompt` (an LLM yes/no), and `agent`. Author `command` handlers as
  scripts unless a non-script handler is clearly required. [E2]

Each event exposes different inputs and a different blocking power, so the wrong event cannot
do the job no matter how the handler is written. Select the event first, then the matcher,
then the handler. [E2]

## Which event for which job (E2)

| Job | Event | Matcher example | Can block | Key inputs |
| --- | --- | --- | --- | --- |
| Gate or validate before a tool runs | PreToolUse | `Edit\|Write`, `Bash` | yes (exit 2 or `permissionDecision: deny`) | `tool_name`, `tool_input` |
| Format, lint, or remind after a tool succeeds | PostToolUse | `Edit\|Write` | block before next model call only | `tool_name`, `tool_input`, `tool_output` |
| Boot or inject context at session start | SessionStart | `startup`, `resume`, `clear`, `compact` | no | `source` |
| Savepoint before compaction | PreCompact | `manual`, `auto` | no (savepoint; exits 0) | compaction trigger |
| Erase or augment a prompt before processing | UserPromptSubmit | (none) | yes (exit 2) | `prompt`, `permission_mode` |

Notes that change the choice of event: [E2]

- PreToolUse fires before the tool runs and can stop it. Use it for gates and pre-act
  validation (block an edit to project code before the plan exists, block a destructive
  Bash command).
- PostToolUse fires after the tool has already run. It cannot undo the tool. Use it to format
  the result, lint it, or surface a reminder, and to block the next model call when the
  output is unacceptable.
- SessionStart cannot block. Use it to inject boot context, not to enforce anything. Its
  stdout on exit 0 becomes conversation context (see exit codes).
- PreCompact fires before the runtime compacts the conversation. Use it to write a savepoint
  while the full context still exists.

Plastic ships working instances of each: `scripts/hook-code-gate` (PreToolUse gate),
`scripts/hook-session-start` (SessionStart boot and inject), `scripts/hook-savepoint-pre`
(PreCompact savepoint). Read one before authoring a new hook of the same shape.

## Path rules and executability (E3)

Two failures here are silent: the hook never fires and nothing reports why. [E3]

- Reference the handler script through the exported placeholders: `${CLAUDE_PLUGIN_ROOT}` for
  a script shipped inside a plugin, `${CLAUDE_PROJECT_DIR}` for a script that lives in the
  project. A relative path resolves against an unpredictable working directory; a hard-coded
  absolute path works in development and breaks on another machine. [E3]
- Make the script executable: `chmod +x` the handler file and commit that bit. A
  non-executable `command` handler fails silently. [E3]
- Give the script a shebang (`#!/usr/bin/env ruby` for Plastic hooks; any shell must run under
  macOS /bin/bash 3.2). [E3]

Other placeholders the runtime exports: `${CLAUDE_PLUGIN_DATA}`. [E3]

## No-op by default, opt-in (E4)

Make a hook a no-op by default and enable it only through explicit config. Exit 0 (allow,
emit nothing) unless the user has opted in. A reminder or validation hook that fires for users
who never enabled it blocks or noises work that was never asked for. [E4]

Concrete shape of an opt-in, no-op-by-default handler:

```ruby
#!/usr/bin/env ruby
# PostToolUse reminder. No-op unless explicitly enabled.
require "json"
config = ENV["CLAUDE_PROJECT_DIR"] ? File.join(ENV["CLAUDE_PROJECT_DIR"], ".myhook.yml") : nil
exit 0 unless config && File.exist?(config)   # opt-in gate: silent allow when not enabled
payload = JSON.parse($stdin.read) rescue {}
# ... emit reminder only past this point ...
exit 0
```

The early `exit 0` is the opt-in gate. Place the enable check before any side effect. [E4]
Plastic gate hooks follow the same fail-open discipline: no bridge resolved means exit 0
(allow), seen in `scripts/hook-code-gate`.

## Exit codes and output channels (E5)

The exit code, not the script's intent, decides what the runtime does with the output. [E5]

| Exit code | Meaning | Where output goes |
| --- | --- | --- |
| 0 | success | stdout shown; for UserPromptSubmit and SessionStart, stdout becomes conversation context |
| 2 | blocking error | stdout and JSON ignored; stderr fed back to Claude; blocks the action on events that support blocking |
| other non-zero | non-blocking error | first stderr line in transcript, full text in debug log; action proceeds |

Rules that follow from the table: [E5]

- To inject context (SessionStart boot banner, UserPromptSubmit augmentation), exit 0 and
  write the context to stdout. On those two events stdout is consumed as context, not just
  displayed.
- To block (a gate that refuses an edit, a validator that rejects a command), exit 2 and write
  the reason to stderr. The agent reads stderr and can act on it. Plastic gates do exactly
  this: `$stderr.puts "PLASTIC GATE - <reason>"; exit 2`.
- For PreToolUse, prefer the structured decision over a bare exit. Emit
  `hookSpecificOutput.permissionDecision` with value `allow`, `deny`, `ask`, or `defer`, plus
  `permissionDecisionReason`. Do not use the deprecated top-level `decision` field. [E5]
- Blocking with exit 2 works only on events that support it. PreToolUse is the clear gate
  event; UserPromptSubmit, Stop, SubagentStop, and a few task events also support exit-2
  blocking. SessionStart and SessionEnd cannot block; exit 2 there does not stop anything.
  PreCompact runs a savepoint, not a gate (see the job table). [E5]

PreToolUse JSON shape:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Plan not yet written; edits to project code are gated."
  }
}
```

`hookSpecificOutput` requires `hookEventName`. [E5]

## Verify the harness engaged (E6)

A hook that is configured is not a hook that ran. Verify engagement before relying on a hook
to hold a behavior. [E6]

The known failure: in background sessions the session-id environment variable can be unset, so
hooks that resolve their state through the session (Plastic gates and savepoints resolve a
per-session bridge) silently no-op. The work proceeds ungated and nothing reports it. [E6]
This claim is grounded mainly in Plastic's own operation rather than independent reports; treat
it as Plastic-specific until confirmed elsewhere (LOW-EVIDENCE per E6).

Verify by observation, not assumption: [E6]

- Trigger the event and confirm the side effect (the gate blocked, the savepoint file appeared,
  the boot context showed). Absence of an error is not proof the hook ran.
- Check the session-id environment variable is set in the context where the hook must fire;
  if it is unset, session-scoped hooks no-op.
- For a gate, attempt the action the gate should block and confirm it is refused. A gate that
  never refuses in testing is a gate that is not engaged.

## Authoring checklist

- [ ] Behavior must hold deterministically; a stronger skill description was tried first (E1).
- [ ] Event chosen for its inputs and blocking power; matcher scopes it; handler is a script
      unless another handler type is required (E2).
- [ ] Script referenced through `${CLAUDE_PLUGIN_ROOT}` or `${CLAUDE_PROJECT_DIR}`, has a
      shebang, and is `chmod +x` (E3).
- [ ] No-op by default; the opt-in check runs before any side effect; exits 0 when not enabled
      (E4).
- [ ] Exit codes deliberate: 0 to allow or inject context, 2 to block with the reason on
      stderr; PreToolUse uses `hookSpecificOutput.permissionDecision`, not top-level `decision`
      (E5).
- [ ] Engagement verified by triggering the event and observing the side effect, including the
      unset-session-id no-op case (E6).
