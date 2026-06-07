---
name: update
description: Use when updating Plastic after a plugin update, or when the user says "update plastic". Runs the npx installer to sync core files and re-register agent adapters.
---

# Update Plastic

## When to Use
- User says "update plastic", "sync plastic", or "upgrade plastic"
- Statusline shows "Plastic update available"
- After a version bump notification

## Prerequisites

Global install must exist (`~/.plastic/INDEX.md` present). If not, tell the
user to run `npx @zalom/plastic@latest` first.

## Procedure

### Step 1: Verify global install exists

```bash
if [ ! -f ~/.plastic/INDEX.md ]; then
  echo "No global install found. Run: npx @zalom/plastic@latest"
  exit
fi
```

### Step 2: Run the installer

```bash
npx @zalom/plastic@latest --claude
```

This re-runs the installer which:
- Downloads the latest version from npm
- Syncs core files (PLASTIC.md, scripts, hooks) to ~/.plastic/
- Re-registers hooks and skills into Claude Code's ~/.claude/
- Preserves all user data (INDEX.md, config.yml, projects.yml, store/)

### Step 3: Announce key changes

After the installer completes, read `~/.plastic/PLASTIC.md` and announce any
convention changes that affect the current session. This corrects the agent's
in-context understanding without needing /clear.

Format:
```
Plastic updated to vX.Y.Z.

Key changes in this version:
- [list notable convention changes if any]

Recommendation: run /clear for a clean session with all new conventions loaded.
```

### Step 4: Commit

```bash
cd ~/.plastic && git add PLASTIC.md scripts/ AGENTS.md VERSION 2>/dev/null && git commit -m "chore: update Plastic core files" --allow-empty
```

### Step 5: Clear update cache

```bash
rm -f ~/.plastic/.cache/update-check.json
```

This removes the statusline warning since the update is now applied.
