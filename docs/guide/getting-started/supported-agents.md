# Supported agents

| Agent | Found by | State |
| ----- | -------- | ----- |
| Claude Code | `~/.claude` or the `claude` program | Supported |
| Codex CLI | `~/.codex` or the `codex` program | Supported |
| Hermes | none | Not supported: `plastic init` never installs into it |

`plastic init` lists each supported agent it finds, already picked, and installs Plastic into
the ones you keep.

The `plastic` command itself needs no agent. It runs in any shell with Ruby 4.0 or later.

[Harness support](../../reference/harness-adapters.md) holds the detail for each agent.
[Using Plastic with Claude Code](../../guides/using-plastic-with-claude-code.md) walks through
one of them.
