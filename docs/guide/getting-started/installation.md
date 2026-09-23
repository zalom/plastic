# Installation

```bash
npx -y @zalom/plastic install --claude
plastic version
```

The first line installs Plastic for Claude Code. The second line confirms that the `plastic`
command runs.

The first install also makes `~/.plastic` a Git repository, and registers each store with QMD
when QMD is on the machine. QMD is an optional local search tool for Markdown files.

## Channels

The package version selects the channel. The following table lists the three channels:

| Package | Channel |
| ------- | ------- |
| `@zalom/plastic@latest` | Stable. A first install uses it. |
| `@zalom/plastic@beta` | Beta. |
| `@zalom/plastic@alpha` | Alpha. |

`plastic update` stays on the channel of the installed version, which `~/.plastic/VERSION`
records. To move an installed Plastic to another channel, run `plastic update --beta`,
`plastic update --alpha` or `plastic update --latest`.

## What uninstall removes

`plastic uninstall` removes the agents and hooks that the installer wrote into your
agent's directory, and the managed block in `CLAUDE.md` or `AGENTS.md`. It keeps `~/.plastic`,
which holds your stores. To delete the stores as well, remove `~/.plastic` yourself.

[INSTALL.md](../../../INSTALL.md) covers Codex CLI, a clean Mac, updates and rollback.
[SECURITY.md](../../../SECURITY.md) lists every place the installer writes.
