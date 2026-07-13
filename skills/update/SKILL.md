---
name: plastic-update
description: Use when updating Plastic. Runs the `update` verb, which reads the installed VERSION, derives its channel, queries npm dist-tags, and advances to the next version on that channel (or switches channel with a flag).
user-invocable: true
---

# Update Plastic

## When to Use
- User says "update plastic", "sync plastic", or "upgrade plastic"
- Statusline shows "Plastic update available"
- After a version-bump notification

## What it does

`update` is a single deterministic command. It reads `~/.plastic/VERSION`, derives the
channel from the version string (`-alpha`/`-beta`/none -> stable), queries `npm` dist-tags,
and advances to the **next version on the current channel**. "Already up to date" is a
clean no-op. You do not compute the target yourself, the script does.

## Channel rule

If Plastic is installed, derive `<channel>` from `~/.plastic/VERSION`: a version containing
`-alpha` means `@alpha`, `-beta` means `@beta`, otherwise `@latest`. If not installed
(first install), default to `@latest`. The user can always override with
`--alpha` / `--beta` / `--latest`.

## Flags

| Flag | Behaviour |
|------|-----------|
| (none) | Advance to the next version on the **current** channel |
| `--latest` | Switch to / advance the **stable** channel (toward stability, frictionless) |
| `--beta` | Switch to / advance the **beta** channel |
| `--alpha` | Switch to / advance the **alpha** channel (bleeding edge, confirmed if moving down in stability) |

Switching toward a more stable channel is frictionless; switching toward bleeding edge is
confirmed. To roll **back** to a previously-installed version, use `plastic-rollback`.

## Prerequisites

Plastic must be installed (`~/.plastic/VERSION` present). If not, run `plastic-install`
first (or `npx -y @zalom/plastic@latest install --claude` directly).

## Procedure

### Step 1: Run the update

```bash
npx -y @zalom/plastic@<channel> update --claude
# channel switch: append --beta / --latest / --alpha
# other agents: append --codex / --hermes / --all
```

`bunx -y @zalom/plastic@<channel> update --claude` works as a fallback if `npx` is
unavailable. The command prints the transition (`vX -> vY`) or "already up to date", runs
a post-update doctor summary, and records the move in the append-only
`~/.plastic/versions.json` ledger.

### Step 2: Ask the advisor question once, if unset (Claude Code only)

If this update brought in the advisor feature and `advisor.claude.default` is still
unset in `~/.plastic/config.yml`, ask the same question `plastic-install` asks on a
fresh install, once, then never again (a key already set is respected, never re-asked):
> "Which advisor should be the default?"
> - **Faux Fable** (recommended): Opus 4.8 carrying the frontier reasoning
>   instructions. Much cheaper, available on any plan, reasons in the same
>   disciplined way.
> - **Fable 5**: the frontier model itself. The strongest reasoning available,
>   billed through usage credits, so summon it for a few rounds and close it.

Write the answer with `npx -y @zalom/plastic@<channel> install --claude --reinstall
--advisor faux` (or `--advisor real`). Non-interactive sessions skip the question; the
`plastic-agent-advisor` skill's own routing falls back to `plastic-faux-advisor` at
consult time, so nothing is silently broken by leaving the key unset.

### Step 3: Relay the result, announce convention changes

Relay what `update` printed, do not recompute the version transition or the doctor
summary:

```
Plastic update (<channel>)
Command:  npx -y @zalom/plastic@<channel> update --claude <flags>
Version:  <before> -> <after>
Doctor:   <relayed summary, or "all clear">
```

Then read `~/.plastic/PLASTIC.md` and announce convention changes that affect the
current session, and recommend `/clear` for a clean session with all new conventions
loaded.

### Step 4: Health check only on a relayed failure

If the relayed doctor summary shows a failure, invoke `plastic-doctor` for the full
report and offer to fix. If it already reads clean, do not re-run doctor.

### Step 5: Commit + clear update cache

```bash
cd ~/.plastic && git add PLASTIC.md scripts/ AGENTS.md VERSION versions.json 2>/dev/null && git commit -m "chore: update Plastic to $(cat ~/.plastic/VERSION)" --allow-empty
rm -f ~/.plastic/.cache/update-check.json
```
