# Installation

```bash
curl -fsSL https://raw.githubusercontent.com/zalom/plastic/main/install.sh | sh
plastic init
plastic version
```

The first line installs the newest stable release from GitHub and links `~/.local/bin/plastic`.
The second line lists the agent harnesses found on the machine, such as Claude Code and Codex,
and installs Plastic into each one you pick. The third line confirms that the `plastic` command
runs.

The first install also makes `~/.plastic` a Git repository, and registers each store with QMD
when QMD is on the machine. QMD is an optional local search tool for Markdown files.

## Channels

`install.sh` reads the stable channel unless `PLASTIC_CHANNEL` names `beta` or `alpha`:

```bash
curl -fsSL https://raw.githubusercontent.com/zalom/plastic/main/install.sh | PLASTIC_CHANNEL=alpha sh
```

`plastic update` stays on the channel of the active release. To move to another channel, run
`plastic update --channel stable`, `plastic update --channel beta` or `plastic update --channel alpha`.

## What uninstall removes

`plastic uninstall` removes the agents and hooks that the installer wrote into your
agent's directory, and the managed block in `CLAUDE.md` or `AGENTS.md`. It keeps `~/.plastic`,
which holds your stores. To delete the stores as well, remove `~/.plastic` yourself.

[INSTALL.md](../../../INSTALL.md) covers Codex CLI, a clean Mac, updates and rollback.
[SECURITY.md](../../../SECURITY.md) lists every place the installer writes.
