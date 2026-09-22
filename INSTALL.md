# Install Plastic

Plastic needs Ruby 4.0 or later. The npm install path also needs Node.js 18 or later,
because `npx` fetches the package. After the install, the `plastic` command runs on Ruby
alone.

## Install from npm

```bash
npx -y @zalom/plastic install --claude
```

Replace `--claude` with `--codex` for Codex CLI. Pass both flags to install for both agents.

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
| `plastic update` | Moves Plastic to the next version on its channel. |
| `plastic rollback [--version VERSION]` | Moves to a version this machine has run before. With no version, it lists them. |
| `plastic uninstall` | Removes Plastic from this machine's agents. Your stores stay. |

## Repair an install

Run the installer again when skills are missing or hooks do not fire:

```bash
plastic install --reinstall --claude
```

The installer is safe to repeat.

## A clean Mac

macOS ships Ruby 2.6, which is too old. Install a newer Ruby first:

```bash
curl https://mise.run | sh
mise use --global ruby@4.0
```

The installer checks the Ruby version before it writes anything.

## Install without npm

`install.sh` always installs the latest stable release. It downloads that release's archive,
unpacks it under `~/.local/share/plastic` and links `~/.local/bin/plastic`. It needs Ruby and
curl.

```bash
curl -fsSL https://raw.githubusercontent.com/zalom/plastic/main/install.sh | sh
plastic install --claude
```

To move an installed Plastic to another channel, run `plastic update --beta` or
`plastic update --alpha`.

No stable release carries the archive yet. Until the first one does, the script reports
that and exits, and npm is the way to install.

For what the installer writes on your machine, see [SECURITY.md](SECURITY.md).
