# Install Plastic

Plastic installs from a GitHub release with one shell script, `install.sh`. The `plastic`
command then installs itself into your agent harnesses, and it updates, rolls back and uninstalls
itself.

## What you need

- Ruby 4.0 or later
- git
- curl and tar
- `sha256sum` or `shasum`

When one is missing, `install.sh` stops before it writes anything and names the steps for
macOS and Linux. `install.sh` downloads no Ruby and installs no gem. On Windows, install Plastic
inside WSL; there is no native Windows install.

## A clean Mac

The Ruby 2.6 that macOS ships is too old. Install a newer one first:

```bash
brew install ruby
export PATH="$(brew --prefix ruby)/bin:$PATH"
```

`install.sh` runs the first `ruby` on your `PATH`, and the launcher it writes keeps that Ruby's full path.
When the Ruby is later removed, the launcher prints one line that names `install.sh`; run it again.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/zalom/plastic/main/install.sh | sh
plastic init
```

`plastic init` lists the agent harnesses it finds, each one picked: Claude Code when
`~/.claude` or the `claude` program is there, and Codex CLI when `~/.codex` or the `codex`
program is there. It installs Plastic into each harness you pick. Answer with numbers separated
by commas (`1,2`), `a` for all, or `q` to leave with no change. Run from inside an agent, it
prints the list and stops, and the agent runs `plastic init ANSWER` with your answer. After an
install into Codex, open `/hooks` in Codex and trust the changed Plastic hooks.

Each install writes a record under `~/.plastic/installations/`, one file for each harness. The
record lists the files, hooks, settings entries and instruction sections Plastic wrote there.

`install.sh` does these things:

1. Checks for Ruby 4.0 or later, git, curl, tar and a checksum program, and stops with the steps
   to install each one that is missing.
2. Reads the release list from GitHub and picks the newest stable release.
3. Downloads the release archive, its `.sha256` checksum file and its manifest over HTTPS.
4. Checks the archive against the checksum, and refuses an archive that holds a link or a path
   outside it.
5. Unpacks the release into its own directory under `~/.local/share/plastic/releases` and writes a
   launcher that starts your Ruby by its full path.
6. Points the `active` link at the new release, and links `~/.local/bin/plastic` to it.

A failed download or checksum leaves the installed release as it was. The script edits no
shell profile. When `~/.local/bin` is not on your `PATH`, it prints the line to add.

`sh install.sh --dry-run` reads the release metadata and changes nothing. `PLASTIC_VERSION`
installs one named stable release instead of the newest. `PLASTIC_RUBY` names a Ruby to run
instead of the first one on your `PATH`.

`plastic update` downloads the newest release into `~/.local/share/plastic/download`, checks it
against its checksum, and prints the command that installs it. `plastic rollback` changes nothing
and prints the command that switches back to the previous release.

The last line of `install.sh` names the next command. On a first install it is
`plastic init`. When Plastic is already installed, `install.sh` brings the agent files in
line with the new release, and the next command is `plastic version`.

## Enola

Enola maps the code architecture of a
project. It is optional, and Plastic works without it. To install it, run its official
installer:

```bash
curl -fsSL https://raw.githubusercontent.com/enola-labs/enola/main/install.sh | sh
```

Plastic runs no Enola installer, pins no Enola release and stores no Enola preference.

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

`plastic update` activates the newest stable release. `--dry-run` names both versions and
changes nothing. Contributors who follow a pre-release channel read
[the release lines](docs/release-lines.md#follow-a-pre-release-channel).

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
plastic uninstall
```

`plastic uninstall` lists the harnesses Plastic is installed into, each one picked, and the
other registered harnesses it finds. From each harness you pick, it removes exactly what that
harness's record lists, so your own settings entries stay. `--dry-run` lists what the command
would remove or change. Your stores under `~/.plastic` stay.

Once Plastic is installed into no harness, the command also removes the releases under
`~/.local/share/plastic` and the `~/.local/bin/plastic` link. A `plastic` file there that
Plastic did not link stays, and the command says so.

## Move from npm

Plastic no longer publishes to npm. The stable release 2.0.3 stays on npm and still installs
with `npx -y @zalom/plastic install --claude`. Nothing newer goes to npm. Every later release
is a GitHub release that `install.sh` installs.

The `plastic update` of 2.0.3 reads npm, so it finds nothing newer and stays on 2.0.3. Run
`install.sh` once to move. After that, `plastic update` reads the GitHub releases.

To move an npm installation, run `install.sh` once:

```bash
curl -fsSL https://raw.githubusercontent.com/zalom/plastic/main/install.sh | sh
```

The script removes the hooks that ran `~/.plastic/bin/plastic` or `~/.plastic/exe/plastic` and points them at the active
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

`install.sh` targets macOS and Linux, including WSL. It needs Ruby 4.0 or later and git on `PATH`.
The hosted tests run on Linux. Other platforms are not verified by a hosted run.

Report a problem on a platform that is not verified as an issue at
<https://github.com/zalom/plastic/issues>.

## What the installer writes

For every file the installer writes on your machine, see [SECURITY.md](SECURITY.md).
