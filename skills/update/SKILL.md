---
name: plastic-update
description: Use when updating Plastic. Runs the `update` verb, which reads the installed VERSION, derives its channel, queries npm dist-tags, and advances to the next version on that channel (or switches channel with a flag).
---

# Update Plastic

## When to Use
- User says "update plastic", "sync plastic", or "upgrade plastic"
- Statusline shows "Plastic update available"
- After a version-bump notification

## What it does

`update` is a single deterministic command. It reads `~/.plastic/VERSION`, derives the
channel from the version string (`-alpha`/`-beta`/none → stable), queries `npm` dist-tags,
and advances to the **next version on the current channel**. "Already up to date" is a
clean no-op. You do not compute the target yourself — the script does.

## Flags

| Flag | Behaviour |
|------|-----------|
| (none) | Advance to the next version on the **current** channel |
| `--latest` | Switch to / advance the **stable** channel (toward stability — frictionless) |
| `--beta` | Switch to / advance the **beta** channel |
| `--alpha` | Switch to / advance the **alpha** channel (bleeding edge — confirmed if moving down in stability) |

Switching toward a more stable channel is frictionless; switching toward bleeding edge is
confirmed. To roll **back** to a previously-installed version, use `plastic-versions`.

## Prerequisites

Plastic must be installed (`~/.plastic/VERSION` present). If not, run
`npx @zalom/plastic install --claude` first.

## Procedure

### Step 1: Run the update

```bash
npx @zalom/plastic update            # next version on the current channel
# or: npx @zalom/plastic update --beta   /   --latest   /   --alpha
```

Append the agent flag(s) if not just Claude (`--codex`, `--hermes`, `--all`).
The command prints the transition (`vX → vY`) or "already up to date", and records the
move in the append-only `~/.plastic/versions.json` ledger.

### Step 2: Announce key changes

After it completes, read `~/.plastic/PLASTIC.md` and announce convention changes that
affect the current session:

```
Plastic updated to vX.Y.Z (channel).

Key changes:
- [notable convention changes, if any]

Recommendation: run /clear for a clean session with all new conventions loaded.
```

### Step 3: Health check

Invoke `plastic-doctor`. If all checks pass: **"Health check: all clear."** Otherwise show
the report and offer to fix.

### Step 4: Commit + clear update cache

```bash
cd ~/.plastic && git add PLASTIC.md scripts/ AGENTS.md VERSION versions.json 2>/dev/null && git commit -m "chore: update Plastic to $(cat ~/.plastic/VERSION)" --allow-empty
rm -f ~/.plastic/.cache/update-check.json
```
