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
| `plastic rollback [--version VERSION]` | Switches back to the previous release that `install.sh` activated, or to the installed release you name. `--dry-run` names the switch and changes nothing. |
| `plastic uninstall` | Removes Plastic from this machine's agents. Your stores stay. |

## Repair an install

Run the installer again from the package when hooks or agents are missing:

```bash
npx -y @zalom/plastic install --reinstall --claude
```

Run it through `npx`, not through the installed `plastic` command. In 2.0.2 the installed copy
stops with `same file` when it reinstalls onto itself.

The installer is safe to repeat.

## A clean Mac

macOS ships Ruby 2.6, which is too old. Install a newer Ruby first:

```bash
curl https://mise.run | sh
mise use --global ruby@4.0
```

The installer checks the Ruby version before it writes anything.

## Install the Ruby dependency

Plastic's retrieval commands require sqlite3 version 2.9.6. The npm package ships
the Ruby source and does not include `Gemfile.lock`, so install the required version
in the Ruby you use to run `plastic`:

```bash
gem install sqlite3 -v 2.9.6
```

Run this command before `plastic install` when the installer reports that the sqlite3
gem is missing.

## Install without npm

`install.sh` installs the newest release on the stable channel, or on the channel that
`PLASTIC_CHANNEL` names (`stable`, `beta` or `alpha`). `PLASTIC_VERSION` picks one release
instead. The script downloads the release's archive, its `.sha256` checksum file and its
manifest over HTTPS, and checks the archive against the checksum before it unpacks anything.
Each release goes into its own directory under `~/.local/share/plastic/releases`, and the
`active` link points at the one in use. The script links `~/.local/bin/plastic` to it and
prints a PATH hint. It edits no shell profile. It needs Ruby 4.0 or later with Bundler, curl,
tar, and `sha256sum` or `shasum`. When one is missing, it names the steps for macOS and Linux.
`sh install.sh --dry-run` reads the release metadata and changes nothing.

```bash
curl -fsSL https://raw.githubusercontent.com/zalom/plastic/main/install.sh | sh
plastic install --claude
```

To move an installed Plastic to another channel, run `plastic update --beta` or
`plastic update --alpha`.

When no release on the channel carries all three files, the script reports that and exits, and
npm is the way to install. A failed download or checksum leaves the installed release as it was.

For what the installer writes on your machine, see [SECURITY.md](SECURITY.md).
