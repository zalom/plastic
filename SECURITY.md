# What Plastic touches on your machine

Plastic runs on your machine. It makes no model call and sends none of your files anywhere.

Three things use the network. The update check hook and `plastic update` ask the npm registry
for the newest version with `npm view @zalom/plastic dist-tags`. The npm install path
downloads the package through `npx`. `plastic session commit` in a project whose flow sets
`mode: pull_request` runs `gh pr create`, which talks to GitHub.

## Files the installer writes

| Place | What is written |
| ----- | --------------- |
| `~/.plastic/` | Scripts, hooks, templates, `PLASTIC.md`, the install ledger `versions.json`, and your stores. |
| `~/.claude/agents/`, `~/.claude/hooks`, `~/.claude/plastic/` | The Plastic agents and hooks for Claude Code, and the install record (`manifest.json`, `VERSION`). No workflow skills ship: the package's `skills/` holds only the shared `_decision-tables.md`, which the installer places in `~/.plastic/`, and `~/.claude/skills` may be left empty. |
| `~/.claude/settings.json` | Hook entries, and the status line when you choose it. |
| `~/.claude/CLAUDE.md` | One managed block between the `BEGIN PLASTIC` and `END PLASTIC` markers. |
| `~/.codex/AGENTS.md`, `~/.codex/hooks.json`, `~/.codex/agents/` | The same, for Codex CLI. |

The installer replaces only its managed block in `CLAUDE.md` and `AGENTS.md`. Text outside
the markers stays as you wrote it. `plastic uninstall` removes what the installer wrote and
leaves your stores in place.

## Your stores

A store is a Git repository of Markdown files under `~/.plastic/`. It can hold private notes.
Plastic never pushes a store. Pushing one is your decision.

## Exit code 3

A command that refuses a step exits with code 3. The step belongs to the owner of the
machine. An agent reports the refusal and stops. It never retries with a different flag.

## Report a problem

Open an issue at <https://github.com/zalom/plastic/issues>. For a problem that exposes private
data, write to the repository owner instead of opening a public issue.
