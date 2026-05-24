---
name: install
description: Use when initializing Plastic in a new project. Creates the .plastic/ directory structure with store/, INDEX.md, and config.yml. Run this after installing the plugin via 'claude plugin add plastic@plastic'.
---

# Install Plastic

Initialize the `.plastic/` intent store in the current project.

## Prerequisites

The Plastic plugin must already be installed:
1. Marketplace registered in `~/.claude/settings.json` under `extraKnownMarketplaces`
2. Plugin installed via `claude plugin add plastic@plastic`

## Procedure

### Step 1: Check for existing installation

Check if `.plastic/` directory already exists in the project root.

- If `.plastic/INDEX.md` exists: announce "Plastic is already initialized in this project." and stop.
- If `.plastic/` exists but is incomplete (missing INDEX.md or config.yml): warn and offer to repair.
- If `.plastic/` does not exist: proceed.

### Step 2: Create directory structure

Create the following structure using templates from the plugin:

```
.plastic/
├── config.yml      # Copy from ${CLAUDE_PLUGIN_ROOT}/templates/config.yml
├── INDEX.md        # Copy from ${CLAUDE_PLUGIN_ROOT}/templates/index.md
└── store/          # Empty directory (add .gitkeep)
```

Read templates from the plugin directory:
- `config.yml` from `${CLAUDE_PLUGIN_ROOT}/templates/config.yml`
- `INDEX.md` from `${CLAUDE_PLUGIN_ROOT}/templates/index.md`

Create `store/` as an empty directory with a `.gitkeep` file to ensure git tracks it.

### Step 3: Git tracking decision

Ask the user:

> "Should intents be tracked in git? (Recommended: yes — intents are lightweight markdown and benefit from version history)"

- **Yes (default):** No action needed. `.plastic/` is tracked normally.
- **No:** Add `.plastic/store/` to the project's `.gitignore`. Keep `.plastic/config.yml` and `.plastic/INDEX.md` tracked.

### Step 4: Commit

```bash
git add .plastic/
git commit -m "chore: initialize Plastic intent store"
```

### Step 5: Announce

> "Plastic initialized. Create your first intent with `/plastic:creating-intent`."
