# Install Plastic

Plastic installs from a GitHub release with one shell script, `install.sh`. The `plastic`
command then installs itself into your agent, and it updates, rolls back and uninstalls
itself.

## What you need

- Ruby 4.0 or later, with Bundler
- curl and tar
- `sha256sum` or `shasum`

When one is missing, `install.sh` stops before it writes anything and names the steps for
macOS and Linux.

## A clean Mac

macOS ships Ruby 2.6, which is too old. Install a newer Ruby first:

```bash
curl https://mise.run | sh
mise use --global ruby@4.0
```

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/zalom/plastic/main/install.sh | sh
plastic install --claude
```

Replace `--claude` with `--codex` for Codex CLI. Pass both flags to install for both agents,
or pass `--all` for every supported agent.

`install.sh` does these things:

1. Reads the release list from GitHub and picks the newest release on the channel.
2. Downloads the release archive, its `.sha256` checksum file and its manifest over HTTPS.
3. Checks the archive against the checksum, and refuses an archive that holds a link or a path
   outside it.
4. Unpacks the release into its own directory under `~/.local/share/plastic/releases`, and has
   Bundler install the sqlite3 gem inside that directory.
5. Points the `active` link at the new release, and links `~/.local/bin/plastic` to it.

A failed download or checksum leaves the installed release as it was. The script edits no
shell profile. When `~/.local/bin` is not on your `PATH`, it prints the line to add.

`sh install.sh --dry-run` reads the release metadata and changes nothing. `PLASTIC_VERSION`
installs one named release instead of the newest.

The last line of `install.sh` names the next command. On a first install it is
`plastic install`. When Plastic is already installed, `install.sh` brings the agent files in
line with the new release, and the next command is `plastic version`.

## Enola

After a first `plastic install`, Plastic offers Enola. Enola maps the code architecture of a
project. It is optional, and Plastic works without it. To install it, run its official
installer:

```bash
curl -fsSL https://raw.githubusercontent.com/enola-labs/enola/main/install.sh | sh
```

Plastic prints this offer and nothing more. It runs no Enola installer, pins no Enola release
and stores no Enola preference. A reinstall, an update and a rollback make no offer.

## Channels

Plastic has three channels: stable, beta and alpha. `install.sh` reads stable unless
`PLASTIC_CHANNEL` names another:

```bash
curl -fsSL https://raw.githubusercontent.com/zalom/plastic/main/install.sh | PLASTIC_CHANNEL=alpha sh
```

When no release on the channel carries the archive, the checksum and the manifest, the
script says so and exits.

## Check the installation

```bash
plastic version
```

`plastic version` prints the version, the channel and the file it read them from. It then
checks each part of the installation:

| Row | What it checks |
| --- | -------------- |
| `active` | The release the `active` link points at |
| `previous` | The release that `plastic rollback` switches back to |
| `launcher` | The first `plastic` on your `PATH`, and whether it is the linked launcher |
| `ruby` | The Ruby version, which must be 4.0 or later |
| `sqlite3 bundle` | Whether the active release holds its sqlite3 gem |
| `hooks` | Whether the agent hooks run the active release |
| `installer lock` | Whether an installer is running, or an activation was interrupted |

The check changes nothing. For each broken part it prints a `repair:` line with the command
that fixes it, and it exits 1. Run the repairs, then run `plastic version` again.

When no release is installed, as when Plastic runs from source or from npm, the `installation`
row says so. Only Ruby is checked, and the check does not report the installation as whole.

## Update

```bash
plastic update
```

`plastic update` activates the newest release on the channel of the active release.
`--dry-run` names both versions and changes nothing.

To move to another channel, name it:

```bash
plastic update --beta
plastic update --alpha
plastic update --stable
```

An update keeps the release it replaces, so a rollback can return to it. It brings the agent
files in line with the new release. It does not touch your stores or their databases.

## Roll back

```bash
plastic rollback
plastic rollback --version 2.0.4
```

`plastic rollback` switches the `active` link back to the previous release. `--version`
switches to another installed release. `--dry-run` names the switch and changes nothing.

A rollback changes only which program runs. It does not reverse a change to your stores.

## Interrupted installs

Every install, update and rollback holds an installer lock under
`~/.local/share/plastic`, so two cannot run at once. Each one writes a record of the switch
before it makes it. When an installer stops halfway, the next run restores the interrupted
activation before it changes anything. `plastic version` reports an interrupted activation
until then.

## Uninstall

```bash
plastic uninstall --all
```

`plastic uninstall` removes the hooks, agents and conventions that Plastic registered with
your agents. Pass `--claude` or `--codex` to remove one agent only. `--dry-run` lists what
the command would remove. Your stores under `~/.plastic` stay.

Once no agent stays registered, the command also removes the releases under
`~/.local/share/plastic` and the `~/.local/bin/plastic` link. A `plastic` file there that
Plastic did not link stays, and the command says so.

## Move from npm

npm is frozen at the stable release 2.0.3. That release stays installable with
`npx -y @zalom/plastic install --claude`. Nothing newer is published to npm, so every later
release installs through `install.sh`.

To move an npm installation, run `install.sh` once:

```bash
curl -fsSL https://raw.githubusercontent.com/zalom/plastic/main/install.sh | sh
```

The script removes the hooks that ran `~/.plastic/bin/plastic` and points them at the active
release. Your stores, `config.yml` and your agent settings stay.

If you linked `~/.local/bin/plastic` to `~/.plastic/bin/plastic` by hand, as the npm
instructions said, the script leaves that link alone and says so. Move it aside and run the
script again:

```bash
mv ~/.local/bin/plastic ~/.local/bin/plastic.npm
curl -fsSL https://raw.githubusercontent.com/zalom/plastic/main/install.sh | sh
```

After the move, `plastic version` names the launcher and the hooks. Both should point at the
active release.

## Supported platforms

`install.sh` targets macOS and Linux, including WSL. The evidence differs by platform:

| Platform | Evidence |
| -------- | -------- |
| macOS on Apple silicon | Install, update and rollback checked by hand |
| Linux on x86_64 | The test suite runs in CI; no install checked by hand |
| macOS on Intel | Not verified |
| Linux on ARM | Not verified |
| WSL | Not verified |

Report a problem on a platform that is not verified as an issue at
<https://github.com/zalom/plastic/issues>.

## What the installer writes

For every file the installer writes on your machine, see [SECURITY.md](SECURITY.md).
