# Install Plastic

Plastic installs from a GitHub release with one shell script, `install.sh`. The `plastic`
command then installs itself into your agent, and it updates, rolls back and uninstalls
itself.

## What you need

- curl and tar
- `sha256sum` or `shasum`

When one is missing, `install.sh` stops before it writes anything and names the steps for
macOS and Linux.

You need no Ruby of your own: `install.sh` brings Ruby 4.0.7. It runs on macOS, and on Linux with glibc 2.29 or later. Alpine and other musl systems
are not supported. On Windows, install Plastic inside WSL; there is no native Windows install.

## A clean Mac

A clean Mac needs nothing more. `install.sh` brings the Ruby Plastic runs on, so Plastic never
uses the Ruby 2.6 that macOS ships.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/zalom/plastic/main/install.sh | sh
plastic install --claude
```

Replace `--claude` with `--codex` for Codex CLI. Pass both flags to install for both agents,
or pass `--all` for every supported agent.

`install.sh` does these things:

1. Picks the Ruby build for your platform: a jdx/ruby build on Apple silicon and Linux, or the
   Homebrew portable Ruby on an Intel Mac. A Rosetta shell on Apple silicon gets the Apple silicon
   build. It checks the download against its pinned size and SHA-256, refuses an archive that holds
   a link or a path outside it, starts the Ruby once, and moves it into a read-only directory under
   `~/.local/share/plastic/rubies`. A Ruby already there is reused.
2. Reads the release list from GitHub and picks the newest release on the channel.
3. Downloads the release archive, its `.sha256` checksum file and its manifest over HTTPS.
4. Checks the archive against the checksum, and refuses an archive that holds a link or a path
   outside it.
5. Unpacks the release into its own directory under `~/.local/share/plastic/releases`, has the
   Bundler of that Ruby install the sqlite3 and tty-prompt gems inside that directory, and writes a launcher that
   starts that Ruby by its full path.
6. Points the `active` link at the new release, and links `~/.local/bin/plastic` to it.

A failed download or checksum leaves the installed release as it was. The script edits no
shell profile. When `~/.local/bin` is not on your `PATH`, it prints the line to add.

`sh install.sh --dry-run` reads the release metadata and changes nothing. `PLASTIC_VERSION`
installs one named release instead of the newest.
For development, `PLASTIC_RUBY` names a Ruby to run instead, and `install.sh` downloads no Ruby.

An update reuses the Ruby it already has, or adds the one a newer release pins beside it. Each
release keeps the Ruby it was installed with, so a rollback starts the Ruby the older release ran on.

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

When no release is installed, as when Plastic runs from source or from an npm copy, the `installation`
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

Plastic retired npm on 2026-10-03. The stable release 2.0.3 stays on npm and still installs
with `npx -y @zalom/plastic install --claude`. Nothing newer goes to npm. Every later release
is a GitHub release that `install.sh` installs.

The `plastic update` of 2.0.3 reads npm, so it finds nothing newer and stays on 2.0.3. Run
`install.sh` once to move. After that, `plastic update` reads the GitHub releases.

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

`install.sh` targets macOS and Linux, including WSL. CI installs, updates, rolls back and
uninstalls Plastic with no Ruby on `PATH` on each platform in this table except WSL:

| Platform | Ruby | Evidence |
| -------- | ---- | -------- |
| macOS on Apple silicon | jdx/ruby 4.0.7-2 | CI, and checked by hand |
| macOS on Intel | Homebrew portable Ruby 4.0.7 | CI |
| Linux on x86_64, glibc 2.29 or later | jdx/ruby 4.0.7-2 | CI |
| Linux on ARM, glibc 2.29 or later | jdx/ruby 4.0.7-2 | CI |
| WSL | jdx/ruby 4.0.7-2, as on Linux | Not verified |

Report a problem on a platform that is not verified as an issue at
<https://github.com/zalom/plastic/issues>.

## What the installer writes

For every file the installer writes on your machine, see [SECURITY.md](SECURITY.md).
