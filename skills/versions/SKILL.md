---
name: plastic-versions
description: Use when the user wants to see their Plastic version history or roll back to a previously-installed version after a bad release. Manages the local, append-only versions.json ledger and steps between versions the user has actually run. For moving to a brand-new release, use plastic-update instead.
---

# Plastic Versions — local version time-machine

## When to Use
- "show plastic versions", "version history", "what versions have I run"
- "roll back plastic", "downgrade", "go back to the version that worked", "revert plastic"
- A new version broke something and the user wants their last known-good build

For upgrading to a **new** release, use `plastic-update`. This skill only navigates
versions you have **already installed** — the ones recorded in the ledger.

## The ledger

`~/.plastic/versions.json` is an **append-only JSONL** ledger — one line per version
change, never modified or deleted:

```json
{"version":"1.0.0-alpha.17","action":"install","at":"..."}
{"version":"1.0.0-alpha.18","action":"update","at":"..."}
```

`action` ∈ `install | reinstall | update | downgrade` (derived from version direction; the
channel is derived from the version string, never stored). It is a troubleshooting record.

## Procedure

### Show history

```bash
npx @zalom/plastic versions
```

Prints the table with the currently-installed version marked. If the most recent action was
a `downgrade`, it asks whether to keep rolling back.

### Roll back

```bash
npx @zalom/plastic versions --downgrade                    # one step back
npx @zalom/plastic versions --downgrade --version 1.0.0-alpha.15   # to a specific run
```

Rollback targets are restricted to versions in the ledger (only builds you have actually
run, so you only ever return to something known-good for you). The chosen version is
re-fetched from npm and re-synced; your intent store, config, and the ledger are untouched.

### Step forward (after a rollback)

```bash
npx @zalom/plastic versions --upgrade                      # one step forward in your history
```

### After any change

Run `plastic-doctor` to confirm health, and suggest `/clear` so the session picks up the
swapped conventions.

## Notes
- The ledger is **never** edited or pruned — it is the audit trail.
- Downgrades cannot un-migrate a store-format change; if a warning appears, surface it to
  the user rather than forcing the rollback.
