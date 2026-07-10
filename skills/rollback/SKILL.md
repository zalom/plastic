---
name: plastic-rollback
description: Use when the user wants to see their Plastic version history or roll back to a previously-installed version after a bad release. Manages the local, append-only versions.json ledger and steps between versions the user has actually run. For moving to a brand-new release, use plastic-update instead.
user-invocable: true
---

# Plastic Rollback: local version time-machine

## When to Use
- "show plastic versions", "version history", "what versions have I run"
- "roll back plastic", "downgrade", "go back to the version that worked", "revert plastic"
- A new version broke something and the user wants their last known-good build

For upgrading to a **new** release, use `plastic-update`. This skill only navigates
versions you have **already installed**, the ones recorded in the ledger.

## Read-only by default

A flagless run only prints the version history table. It never switches, never prompts,
and never offers to keep going further back. Switching a version always needs an
explicit target, named with `--version`.

## Channel rule

`rollback` restores whichever build you name from the ledger, it does not take a channel
flag for the target. The pinned `<channel>` below is only the npx invocation itself:
derive it from `~/.plastic/VERSION` the same way as the other lifecycle skills,
`-alpha` to `@alpha`, `-beta` to `@beta`, otherwise `@latest`.

## The ledger

`~/.plastic/versions.json` is an **append-only JSONL** ledger, one line per version
change, never modified or deleted:

```json
{"version":"1.0.0-alpha.17","action":"install","at":"..."}
{"version":"1.0.0-alpha.18","action":"update","at":"..."}
```

`action` is one of `install`, `reinstall`, `update`, `downgrade` (derived from version
direction; the channel is derived from the version string, never stored). It is a
troubleshooting record.

## Procedure

### Show history (read-only, no switch)

```bash
npx -y @zalom/plastic@<channel> rollback
```

Prints the table with the currently-installed version marked. Never switches, never
prompts, no matter what the last recorded action was.

### Switch to a specific version

```bash
npx -y @zalom/plastic@<channel> rollback --version 1.0.0-alpha.15
```

The only way to actually switch. The target must be a version you have actually run (the
ledger); the direction (upgrade or downgrade) is derived automatically by comparing the
target to the installed version.

`--downgrade --version V` and `--upgrade --version V` are accepted as explicit-target
synonyms of `--version V`, the direction flag is descriptive only:

```bash
npx -y @zalom/plastic@<channel> rollback --downgrade --version 1.0.0-alpha.15
npx -y @zalom/plastic@<channel> rollback --upgrade --version 1.0.0-alpha.18
```

A bare `--downgrade` or `--upgrade` with no `--version` is an error: it prints a message
asking for an explicit target and performs no switch.

### After any change

Run `plastic-doctor` to confirm health, then emit the reporting block and suggest
`/clear` so the session picks up the swapped conventions:

```
Plastic rollback (<channel>)
Command:  npx -y @zalom/plastic@<channel> rollback <flags>
Version:  <before> -> <after>
Doctor:   <summary or "all clear">
```

## Notes
- The ledger is **never** edited or pruned, it is the audit trail.
- Switching cannot un-migrate a store-format change; if a warning appears, surface it to
  the user rather than forcing the switch.
