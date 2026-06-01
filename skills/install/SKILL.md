---
name: plastic:install
description: Use when initializing Plastic globally (~/.plastic/) or locally in a project. Global install is recommended — creates the global intent store as a git-backed repository. Local install creates .plastic/ in the current project for testing.
---

# Install Plastic

## Modes

### Global Install (default, recommended)

Run `/plastic:install` with no arguments.

#### Procedure

**Step 1: Check for existing installation**

Check if `~/.plastic/INDEX.md` exists.
- If yes: announce "Plastic is already installed at ~/.plastic/. Run `/plastic:update` to sync core files."
- If no: proceed with fresh install.

**Step 2: Create ~/.plastic/ as a git repo**

```bash
mkdir -p ~/.plastic/store ~/.plastic/projects
```

Copy templates from the plugin:
- `config.yml` from `${CLAUDE_PLUGIN_ROOT}/templates/config.yml`
- `projects.yml` from `${CLAUDE_PLUGIN_ROOT}/templates/projects.yml`
- `INDEX.md` from `${CLAUDE_PLUGIN_ROOT}/templates/index.md`
- `PLASTIC.md` from `${CLAUDE_PLUGIN_ROOT}/PLASTIC.md`

Create `AGENTS.md` (user-editable, not overwritten on updates):
```markdown
# Plastic — Agent Instructions

Read `PLASTIC.md` in this directory. It contains all Plastic conventions.
Follow it exactly. Never modify it — it is overwritten on plugin updates.

This file (`AGENTS.md`) is where project-specific rules live. Users and agents
may add content below.

---
```

Add `.gitkeep` to `store/` and `projects/`.

Initialize git:
```bash
cd ~/.plastic && git init && git add . && git commit -m "chore: initialize Plastic global intent store"
```

**Step 2b: Copy utility scripts**

```bash
mkdir -p ~/.plastic/scripts
cp "${CLAUDE_PLUGIN_ROOT}/scripts/hash-intent" ~/.plastic/scripts/hash-intent
cp "${CLAUDE_PLUGIN_ROOT}/scripts/read-config" ~/.plastic/scripts/read-config
chmod +x ~/.plastic/scripts/hash-intent ~/.plastic/scripts/read-config
```

This ensures project agents can generate hashes via `~/.plastic/scripts/hash-intent` without depending on a specific agent's plugin cache path.

**Step 2c: Detect agent type and set preferences**

Detect which agent is running:
- If `CLAUDE_CODE` env var is set or we're running inside Claude Code → `agent.type: claude-code`
- If `HERMES_HOME` env var is set → `agent.type: hermes`
- Otherwise → ask the user: "Which AI agent are you using? (claude-code / hermes / other)"

Ask the user:
> "Enable Agent Teams? (experimental — parallel project work with teammates)"
> - Yes → set `parallel_mode: agent-teams`
> - No → set `parallel_mode: linear` (subagents only)

Update `~/.plastic/config.yml` with detected/chosen values using `read-config --migrate` first to ensure v3 schema, then write the agent-specific values.

Auto-commit the config change.

**Step 2d: Configure GitHub and push preferences**

Inform the user:
> "Plastic agents can create GitHub repositories for new projects.
> By default, all agent-created repos are **private**. Your global
> intent store (~/.plastic/) is never pushed — it stays local-only."

Ask the user:
> "Default visibility for agent-created repos?"
> - Private (recommended) → set `github.default_visibility: private`
> - Public → set `github.default_visibility: public`

> "Allow agents to push to GitHub without asking?"
> - No (recommended) → set `github.auto_push: false`
> - Yes → set `github.auto_push: true`

Update `config.yml` with chosen values. Auto-commit.

**Step 3: Configure project roots**

Ask the user:
> "Where do you keep your projects? Default: ~/.plastic/projects/"
> "Add additional roots? (e.g., ~/apps/personal/, ~/apps/companies/)"

Update `config.yml` with any additional roots.

Auto-commit the config change.

**Step 4: Announce**

> "Plastic installed globally at ~/.plastic/. Create your first intent with `/plastic:creating-intent`."

### Local Install (testing/legacy)

Run `/plastic:install --local`.

#### Procedure

**Step 1:** Check if `.plastic/` exists in CWD — if so, warn and exit.

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

**Step 5:** Announce: "Plastic initialized locally. This is a testing/legacy mode. Consider `/plastic:install` for global mode."
