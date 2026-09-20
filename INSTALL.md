# Install Plastic

Plastic needs Ruby 3.0 or later. The npm install path also needs Node.js 18 or later,
because `npx` fetches the package. After the install, the `plastic` command runs on Ruby
alone.

## Install from npm

```bash
npx -y @zalom/plastic install --claude
```

Replace `--claude` with `--codex` for Codex CLI. Pass both flags to install for both agents.

To see what the installer would write without writing it, add `--dry-run`:

```bash
npx -y @zalom/plastic install --claude --dry-run
```

## Choose a channel

The package version selects the channel. To install the alpha channel:

```bash
npx -y @zalom/plastic@alpha install --claude
```

## Check the install

```bash
plastic version
plastic status
```

`plastic version` prints the installed version and the file it read it from.
`plastic status` shows the active work in every store.

## Update, roll back, uninstall

| Command | What it does |
| ------- | ------------ |
| `plastic update [--dry-run]` | Moves Plastic to the next version on its channel. |
| `plastic rollback [VERSION] [--list]` | Moves to a version this machine has run before. `--list` shows them. |
| `plastic uninstall [--dry-run]` | Removes Plastic from this machine's agents. Your stores stay. |

## A clean Mac

macOS ships Ruby 2.6, which is too old. Install a newer Ruby first:

```bash
curl https://mise.run | sh
mise use --global ruby@3.3
```

The installer checks the Ruby version before it writes anything.

## Planned

A shell installer, `install.sh`, and publishing from a branch push are planned in intent 376
of the CLI and RLM roadmap. They do not exist yet.

For what the installer writes on your machine, see [SECURITY.md](SECURITY.md).
