---
name: plastic-install
description: 'Use when initializing Plastic globally (~/.plastic/) or locally in a project, or to re-install/repair a broken installation. Accepts channel flags (--alpha, --beta, --latest) to select release channel. First install defaults to --latest (stable); reinstalls match the already-installed channel. Global install is recommended: it creates the global intent store as a git-backed repository. Local install creates .plastic/ in the current project for testing.'
user-invocable: true
---

# Install Plastic

> **Recommended path:** for a first install, run `npx -y @zalom/plastic@latest install --claude`
> in your shell (or `bunx -y @zalom/plastic@latest install --claude` if you use Bun). This skill
> exists to **re-install or repair** an existing setup from inside the agent, and to
> drive interactive global configuration. Whenever this skill performs an install or
> re-install, it **runs `/plastic-doctor` afterward** and reports the result.

## Channel rule

If Plastic is installed, derive `<channel>` from `~/.plastic/VERSION`: a version containing
`-alpha` means `@alpha`, `-beta` means `@beta`, otherwise `@latest`. If not installed
(first install), default to `@latest`. To change channel, pin the package instead of
passing a flag: `npx -y @zalom/plastic@alpha install --claude` (or a version such as
`@2.0.0-alpha.1`); the `--alpha`, `--beta`, and `--latest` flags were removed in 2.0
(intent 310) because they never selected a package.

## Re-install / repair

If Plastic is already installed but something is broken (skills missing, hooks not
firing, leftover legacy plugin), re-run the installer, it is idempotent, prunes
files that no longer ship, and removes any legacy plugin/marketplace layout:

```bash
npx -y @zalom/plastic@<channel> install --reinstall --claude
```

Then **run `/plastic-doctor`** and report what it found.

## Channels

| Package | Channel |
|---------|---------|
| `@zalom/plastic@latest` | stable (default on a first install) |
| `@zalom/plastic@beta` | beta |
| `@zalom/plastic@alpha` | alpha; `npx -y @zalom/plastic@alpha install --claude` is the 2.0 alpha path |

When invoked from within Claude Code (re-install or channel switch), the skill
runs the appropriate npx command:

```bash
# Stable (default on a first install)
npx -y @zalom/plastic@latest install --claude

# Beta
npx -y @zalom/plastic@beta install --claude

# Alpha
npx -y @zalom/plastic@alpha install --claude
```

The installed version and channel are recorded in `~/.plastic/VERSION`.

## Modes

### Global Install (default, recommended)

Run `/plastic-install` with no arguments.

#### Procedure

**Step 1: Run the installer**

Check if `~/.plastic/VERSION` exists.
- If yes: announce "Plastic is already installed at ~/.plastic/. Run `/plastic-update` to
  sync core files, or use the re-install command above to repair in place."
- If no: first ask the advisor question below (Claude Code only), then run the fresh
  install command (default `@latest`, or the channel the user named) with whichever
  flags that answer produced:

```bash
npx -y @zalom/plastic@latest install --claude [--no-advisor] [--advisor VALUE]
```

This single command, via `install.rb` (`bootstrap` + `distribute`), creates `store/`,
`projects/`, `config.yml`, `projects.yml`, `INDEX.md`, and `AGENTS.md` under `~/.plastic/`,
and copies the utility scripts (`folgezettel-id`, `read-config`, and the rest of
`scripts/`). This skill does none of that itself; it wraps the command with the
interactive steps the CLI does not yet own, plus reporting and a doctor pass.

**The advisor (Claude Code only)**

Ask the user one feature question, interactive sessions only:
> "Would you like an advisor agent for expensive reasoning: plan review, architecture
> calls, second opinions, breaking deadlocks?"
> - Yes (recommended) -> ask which advisor is the default, below
> - No -> append `--no-advisor`

If yes, ask which advisor is the default, exactly two choices:
> "Which advisor should be the default?"
> - **Faux Fable** (recommended): Opus 4.8 carrying the frontier reasoning
>   instructions. Much cheaper, available on any plan, reasons in the same
>   disciplined way. -> append `--advisor faux`
> - **Fable 5**: the frontier model itself. The strongest reasoning available,
>   billed through usage credits, so summon it for a few rounds and close it. ->
>   append `--advisor real`

Non-interactive sessions (no tty) skip the question entirely: the install ships with the
shipped default, advisor enabled with no `--advisor` flag (the `plastic-agent-advisor`
skill's own routing falls back to `plastic-faux-advisor` at consult time).

Update flow: pending config questions, including this one, are now announced
generically by `plastic-update`'s Step 2, sourced from `config_asks.yml` - not
duplicated here. A value already set by either path is never re-asked by the
other.

**Statusline**

On install, if an existing statusline is already configured, Plastic asks whether to
keep it or switch to Plastic's (interactive sessions only). The choice is honored via
`--statusline keep` or `--statusline plastic`, which skips the prompt. Non-interactive
sessions (no tty) default to keeping the user's line: nothing is silently overwritten.
A fresh system with no statusline configured gets Plastic's line with no prompt.

**Step 2: Initialize git (retained)**

Only if `~/.plastic/.git` is absent (a fresh bootstrap does not init git):

```bash
cd ~/.plastic && git init && git add . && git commit -m "chore: initialize Plastic global intent store"
```

Retained here because the CLI does not git-init the store yet (follow-up).

**Step 3: Personalize config (retained)**

Detect which agent is running:
- If `CLAUDE_CODE` env var is set or we're running inside Claude Code -> `agent.type: claude-code`
- If `HERMES_HOME` env var is set -> `agent.type: hermes`
- Otherwise -> ask the user: "Which AI agent are you using? (claude-code / hermes / other)"

Ask the user:
> "Enable Agent Teams? (experimental: parallel project work with teammates)"
> - Yes -> set `parallel_mode: agent-teams`
> - No -> set `parallel_mode: linear` (subagents only)

Inform the user:
> "Plastic agents can create GitHub repositories for new projects. By default, all
> agent-created repos are **private**. Your global intent store (~/.plastic/) is never
> pushed, it stays local-only."

Ask the user:
> "Default visibility for agent-created repos?"
> - Private (recommended) -> set `github.default_visibility: private`
> - Public -> set `github.default_visibility: public`
>
> "Allow agents to push to GitHub without asking?"
> - No (recommended) -> set `github.auto_push: false`
> - Yes -> set `github.auto_push: true`
>
> "Where do you keep your projects? Default: ~/.plastic/projects/"
> "Add additional roots? (e.g., ~/apps/personal/, ~/apps/companies/)"

Write each answer via `read-config --migrate` first (ensures the v3 schema), then the
chosen values; auto-commit each change. Retained here because the CLI writes only
hardcoded defaults, so these interactive choices stay in the skill.

**Step 4: Verify with doctor**

Run `/plastic-doctor` and report the result. Resolve any fixable findings before
announcing success.

**Step 5: Register stores with QMD (retained)**

QMD is an optional search layer. If it is installed, register the Plastic stores so
they are searchable:

```bash
ruby ~/.plastic/scripts/qmd-sync detect && ruby ~/.plastic/scripts/qmd-sync register --all
```

`qmd-sync` no-ops cleanly when QMD is absent, so this is safe to run unconditionally.
It registers `plastic-global` and every project store from `projects.yml`, then indexes
them. Report what was registered, or that QMD was not detected and the step was skipped.
Retained here because the CLI does not register at install time (follow-up).

**Step 6: Report + announce**

```
Plastic install (<channel>)
Command:  npx -y @zalom/plastic@<channel> install --claude <flags>
Version:  none -> <installed>
Doctor:   <summary or "all clear">
```

Then: "Read [`your-first-intent-in-10-minutes.md`](https://github.com/zalom/plastic/blob/main/docs/guides/your-first-intent-in-10-minutes.md) for your first intent, start to finish."

### Local Install (testing/legacy)

Run `/plastic-install --local`. `install.rb` has no `--local` verb, so this mode is
genuinely skill-owned.

#### Procedure

**Step 1:** Check if `.plastic/` exists in CWD, if so, warn and exit.

**Step 2:** Create `.plastic/` in CWD:
- `config.yml` from templates
- `INDEX.md` from templates
- `store/` with `.gitkeep`

**Step 3:** If global install exists (`~/.plastic/projects.yml`), register this project:
- Determine project slug from directory name
- Detect git remote URL if available
- Add entry to `~/.plastic/projects.yml` with `parent: null`
- Auto-commit in `~/.plastic/`

**Step 4:** Commit in project: `git add .plastic/ && git commit -m "chore: initialize Plastic local store"`

**Step 5:** Announce: "Plastic initialized locally. This is a testing/legacy mode. Consider
`/plastic-install` for global mode."
