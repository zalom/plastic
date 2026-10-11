# What Plastic touches on your machine

Plastic runs on your machine. It makes no model call and sends none of your files anywhere.

These things use the network. `install.sh`, the update check hook and `plastic update` read
the release list from the GitHub API and download a release archive from GitHub over HTTPS.
`install.sh` and `plastic update` download Ruby from the jdx/ruby releases on GitHub, or from
the Homebrew registry on an Intel Mac, and check it by its pinned size and SHA-256.
Bundler fetches the sqlite3 and tty-prompt gems from RubyGems when a release installs.

## Files the installer writes

| Place | What is written |
| ----- | --------------- |
| `~/.local/share/plastic/` | The releases, the read-only Rubies under `rubies/`, the `active` and `previous` links, the installer lock and the activation record. |
| `~/.local/bin/plastic` | A link to the active release launcher. |
| `~/.plastic/` | Scripts, hooks, the help chapters, `PLASTIC.md`, `deprecations.yml`, the install ledger `versions.json`, and your stores. |
| `~/.claude/agents/`, `~/.claude/hooks`, `~/.claude/plastic/` | The Plastic agents and hooks for Claude Code, and the install record (`manifest.json`, `VERSION`). |
| `~/.claude/settings.json` | Hook entries, and the status line when you choose it. |
| `~/.claude/CLAUDE.md` | One managed block between the `BEGIN PLASTIC` and `END PLASTIC` markers. |
| `~/.codex/AGENTS.md`, `~/.codex/hooks.json`, `~/.codex/agents/` | The same, for Codex CLI. |
| `~/.hermes/agents/`, `~/.hermes/plastic/` | The Plastic agents for Hermes, and the install record. |

The installer replaces only its managed block in `CLAUDE.md` and `AGENTS.md`. Text outside
the markers stays as you wrote it. `plastic uninstall` removes what the installer wrote into your
agents and leaves your stores in place. Once no agent stays registered, it also removes the
releases, the Rubies and the other entries the installer made in `~/.local/share/plastic`, and
the `~/.local/bin/plastic` link. A file you put in that directory stays.

## Your stores

A store is a Git repository of Markdown files under `~/.plastic/`. It can hold private notes.
Plastic never pushes a store. Pushing one is your decision.

## Exit code 3

A command that refuses a step exits with code 3. The step belongs to the owner of the
machine. An agent reports the refusal and stops. It never retries with a different flag.

## Report a problem

Open an issue at <https://github.com/zalom/plastic/issues>. For a problem that exposes private
data, write to the repository owner instead of opening a public issue.
