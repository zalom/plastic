---
name: plastic:update
description: Use when updating Plastic after a plugin update, or when the user says "update plastic". Syncs core files (PLASTIC.md, scripts) to the global store without touching user data.
---

# Update Plastic

## When to Use
- After a plugin update (new version of Plastic installed)
- User says "update plastic", "sync plastic", or "upgrade plastic"
- Something seems out of date in the global store

## Prerequisites

Global install must exist (`~/.plastic/INDEX.md` present). If not, tell the
user to run `/plastic:install` first.

## What Gets Updated

Core files (Plastic-owned, always overwritten):

| File | Source | Destination |
|---|---|---|
| `PLASTIC.md` | `${CLAUDE_PLUGIN_ROOT}/PLASTIC.md` | `~/.plastic/PLASTIC.md` |
| `folgezettel-id` | `${CLAUDE_PLUGIN_ROOT}/scripts/folgezettel-id` | `~/.plastic/scripts/folgezettel-id` |
| `read-config` | `${CLAUDE_PLUGIN_ROOT}/scripts/read-config` | `~/.plastic/scripts/read-config` |

Created if missing (user-owned, never overwritten):

| File | Action |
|---|---|
| `AGENTS.md` | Create with clean starter content if not present |
| `scripts/` dir | Create if not present |

Never touched (user data):

| File | Reason |
|---|---|
| `INDEX.md` | User's intent index |
| `config.yml` | User's preferences |
| `projects.yml` | User's project registry |
| `store/` | User's intents |
| `AGENTS.md` (if exists) | User's project rules and decisions |

## Procedure

### Step 1: Verify global install exists

```bash
if [ ! -f ~/.plastic/INDEX.md ]; then
  echo "No global install found. Run /plastic:install first."
  exit
fi
```

### Step 2: Sync PLASTIC.md

```bash
cp "${CLAUDE_PLUGIN_ROOT}/PLASTIC.md" ~/.plastic/PLASTIC.md
```

### Step 3: Sync scripts

```bash
mkdir -p ~/.plastic/scripts
cp "${CLAUDE_PLUGIN_ROOT}/scripts/folgezettel-id" ~/.plastic/scripts/folgezettel-id
cp "${CLAUDE_PLUGIN_ROOT}/scripts/read-config" ~/.plastic/scripts/read-config
chmod +x ~/.plastic/scripts/folgezettel-id ~/.plastic/scripts/read-config
```

### Step 4: Create AGENTS.md if missing

```bash
if [ ! -f ~/.plastic/AGENTS.md ]; then
  cat > ~/.plastic/AGENTS.md << 'EOF'
# Plastic — Agent Instructions

Read `PLASTIC.md` in this directory. It contains all Plastic conventions.
Follow it exactly. Never modify it — it is overwritten on plugin updates.

This file (`AGENTS.md`) is where project-specific rules live. Users and agents
may add content below.

---
EOF
fi
```

### Step 5: Report

```
Plastic updated.
- PLASTIC.md: synced to latest conventions
- Scripts: synced (folgezettel-id, read-config)
- AGENTS.md: [created | preserved (user-editable)]
- User data: untouched (INDEX.md, config.yml, projects.yml, store/)
```

### Step 6: Commit

```bash
cd ~/.plastic && git add PLASTIC.md scripts/ AGENTS.md 2>/dev/null && git commit -m "chore: update Plastic core files" --allow-empty
```
