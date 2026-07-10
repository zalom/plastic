---
name: plastic-uninstall
description: Use when the user wants to remove Plastic from an agent. Runs the manifest-driven uninstaller (removes skills, hooks, statusline, and any legacy plugin layout), reports exactly what was removed and what was left behind, then gives verification steps. Optionally deletes the intent store.
user-invocable: true
---

# Uninstall Plastic

The installer tracks every file it writes in a manifest, so uninstall is exact and
leaves no orphans. Prefer running it through the CLI; this skill wraps the same
underlying uninstaller and adds reporting + verification.

## Channel rule

If Plastic is installed, derive `<channel>` from `~/.plastic/VERSION`: a version containing
`-alpha` means `@alpha`, `-beta` means `@beta`, otherwise `@latest`. If not installed,
default to `@latest`. The user can always override with `--alpha` / `--beta` / `--latest`.

## Procedure

### Step 1: Run the uninstaller

```bash
npx -y @zalom/plastic@<channel> uninstall --claude
```

(Use `--codex` / `--hermes` / `--all` to target other agents. `bunx -y @zalom/plastic@<channel> uninstall --claude` works too.)

This removes, for the targeted agent:
- all `~/.claude/skills/plastic-*/` skills
- all `~/.claude/hooks/plastic-*` hooks (and restores any saved original statusline)
- the `~/.claude/plastic/` state dir + manifest
- any **legacy** plugin layout: `plugins/marketplaces/plastic`, `plugins/cache/plastic`,
  the old nested `skills/plastic/`, and the `plastic@plastic` /
  `extraKnownMarketplaces.plastic` / `known_marketplaces.json` registrations

### Step 2: Report removed vs left

Relay the uninstaller's output to the user: what was **removed** and what was
**left in place**.
- **Left:** `~/.plastic/` (intent store, history, projects) and any non-Plastic
  settings.json entries.

### Step 3: Verify removal

Tell the user to confirm:

```bash
ls ~/.claude/skills | grep '^plastic-'    # -> no output
ls ~/.claude/hooks  | grep '^plastic-'    # -> no output
grep -n plastic ~/.claude/settings.json   # -> no plastic hook/plugin refs
```

### Step 4: Report + offer the data decision

Emit the reporting block, using the Step 3 checks for the verification line:

```
Plastic uninstall (<channel>)
Command:  npx -y @zalom/plastic@<channel> uninstall --claude <flags>
Version:  removed
Verification: <Step 3 results, or "clean">
```

Then:

```
Plastic is uninstalled from [agent].
Your intent store at ~/.plastic/ is untouched.

Delete it too?
  a) Keep everything (recommended): re-install anytime with npx
  b) Delete everything now: removes ~/.plastic/ entirely (irreversible)
```

- **Keep:** "Your data is at ~/.plastic/. Re-install anytime with
  `npx -y @zalom/plastic@latest install --claude` (or your channel)."
- **Delete:** run `rm -rf ~/.plastic/` and confirm.
