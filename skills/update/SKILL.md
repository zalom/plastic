---
name: plastic:update
description: Use when updating Plastic. Queries npm for available versions across all channels, presents options interactively, or accepts --alpha/--beta/--latest flags for direct update.
---

# Update Plastic

## When to Use
- User says "update plastic", "sync plastic", or "upgrade plastic"
- Statusline shows "Plastic update available"
- After a version bump notification

## Flags

| Flag | Behavior |
|------|----------|
| `--alpha` | Update to latest alpha, skip interactive prompt |
| `--beta` | Update to latest beta, skip interactive prompt |
| `--latest` | Update to latest stable, skip interactive prompt |

No flag = interactive mode (show all available versions).

## Prerequisites

Global install must exist (`~/.plastic/INDEX.md` present). If not, tell the
user to run `npx @zalom/plastic@alpha --claude` first.

## Procedure

### Step 1: Read current version

```bash
cat ~/.plastic/VERSION
```

Parse the version string to determine the current channel:
- Contains `-alpha` → alpha channel
- Contains `-beta` → beta channel
- No pre-release suffix → stable/latest channel

### Step 2: Query npm for available versions

```bash
npm view @zalom/plastic dist-tags --json
```

This returns a JSON object like:
```json
{
  "latest": "0.0.1",
  "alpha": "1.0.0-alpha.14",
  "beta": "1.0.0-beta.2"
}
```

A missing dist-tag means no release exists on that channel.

### Step 3: Present options or act on flag

**If a channel flag was provided** (`--alpha`, `--beta`, `--latest`):

Skip the interactive prompt. Install the flagged channel directly. Go to Step 4.

**If no flag (interactive mode):**

Present the available updates to the user:

```
Currently installed: 1.0.0-alpha.11 (alpha channel)

Available updates:
  alpha:  1.0.0-alpha.14  ← your channel
  beta:   1.0.0-beta.2
  stable: (no stable release yet)

Which channel do you want to install?
```

Use AskUserQuestion with the available channels as options. Mark the user's
current channel with "← your channel". If a dist-tag points to the same
version as currently installed, show "(up to date)" instead of the version.
If a dist-tag doesn't exist, show "(no release yet)".

Wait for user selection.

### Step 4: Run the installer

```bash
npx @zalom/plastic@{selected-tag} --claude
```

Replace `{selected-tag}` with `alpha`, `beta`, or `latest` based on the
user's selection or the flag provided. Replace `--claude` with the appropriate
agent flag(s) — detect current agents from `~/.claude/`, `~/.agents/`,
`~/.hermes/` directories.

### Step 5: Announce key changes

After the installer completes, read `~/.plastic/PLASTIC.md` and announce any
convention changes that affect the current session.

Format:
```
Plastic updated to vX.Y.Z (channel).

Key changes in this version:
- [list notable convention changes if any]

Recommendation: run /clear for a clean session with all new conventions loaded.
```

### Step 6: Run health check

Invoke `plastic:doctor` to verify the installation is healthy after the update.

If all checks pass, show: **"Health check: all clear."**

If issues are found, show the full doctor report and offer to fix.

### Step 7: Commit

```bash
cd ~/.plastic && git add PLASTIC.md scripts/ AGENTS.md VERSION 2>/dev/null && git commit -m "chore: update Plastic to $(cat ~/.plastic/VERSION)" --allow-empty
```

### Step 8: Clear update cache

```bash
rm -f ~/.plastic/.cache/update-check.json
```
