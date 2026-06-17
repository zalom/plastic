---
name: plastic-doctor
description: Use when diagnosing Plastic installation health, after updates, or when something seems broken. Runs checks and reports findings with fix options.
---

# Doctor — Plastic Health Check

## Scopes

Doctor has three scopes. Pick the right one for the situation:

| Scope | Flag | When it runs | States |
|-------|------|--------------|--------|
| Core check | `--core` | SessionStart hook (automatic), also available on demand | Binary: pass or error |
| Store check | `--store [global\|<slug>]` | Dashboard load, `plastic-continuing` | Three-state: pass / warn / fail |
| Full check | (no flag) | After every update (automatic), or `/plastic-doctor` | Three-state: pass / warn / fail |

### `--core` (binary, manifest-backed)

Verifies that every core file is present and content-matches what the installed
version shipped. It checks two install manifests:

- `~/.plastic/manifest.json` (global manifest, covers PLASTIC.md and global scripts)
- `~/.claude/plastic/manifest.json` (agent-side manifest, covers agent scripts and hooks)

Each manifest maps a file path to its SHA256. The core check also confirms hooks
are registered, scripts are present and executable, and the installed version
matches. Result is binary: exit 0 on pass, non-zero on error. It never produces
warnings.

### `--store [global|<slug>]`

Checks store state: intents are well-formed, INDEX sections are present, conventions
are followed, and links are valid. Scope options:

- No argument: checks all stores (global and all projects)
- `global`: checks only the global store
- A project slug (e.g. `--store plastic`): checks only that project's store

Produces three-state results (pass / warn / fail) and is run per-scope at dashboard
load time: the global board uses `--store global`, a project board uses `--store <slug>`.

### Full doctor (no flag)

Runs core plus all store checks plus deprecation checks. This is what `/plastic-doctor`
invokes. It also runs automatically after every `plastic-update` (informational,
does not block or revert the update).

## When to Use

- User invokes `/plastic-doctor` (full check)
- After `plastic-update` completes (automatically, full check)
- When hooks aren't firing, skills aren't loading, or something seems broken
- When the user says "check plastic", "diagnose", "what's wrong with plastic"

## Procedure

### Step 1: Run the diagnostic script

```bash
ruby ~/.plastic/scripts/doctor.rb --agent claude
```

Replace `claude` with the current agent type if known (`codex`, `hermes`).

Parse the JSON output from stdout. The script is read-only and never modifies
files. Errors go to stderr.

Exit codes indicate check results, not script failure:
- `0` — all checks passed
- `1` — warnings found
- `2` — failures found

All three exit codes mean the script ran successfully. Do not treat non-zero
as an error.

### Step 2: Determine overall status

Read the `status` field from the JSON root:

| Status | Meaning |
|--------|---------|
| `pass` | Everything is healthy |
| `warn` | Warnings found but Plastic works normally |
| `fail` | Blocking issues that prevent Plastic from operating |

### Step 3: Fill the report template

Read `report.md` from the same directory as this SKILL.md
(`~/.plastic/skills/doctor/report.md` at runtime, or the plugin source
`skills/doctor/report.md` during development).

Group checks by category. For each category, list the checks with their
status icon and message. If a check has `details`, list them as sub-items.

Present the filled template to the user.

### Step 4: Offer fixes (if applicable)

If any checks have `fixable: true` AND status is not `pass`:

1. Group fixable items by category
2. Show what each fix would do (from `fix_hint`)
3. Ask the user: **"Fix all / Select individually / Skip"**

If no fixable issues exist, skip this step.

### Step 5: Apply fixes

Use the `fix_hint` value to determine the correct action:

| Fix hint pattern | Agent action |
|---|---|
| "chmod +x on the listed files" | Run `chmod +x` on each file listed in `details` |
| "Create missing directory" | Run `mkdir -p` on the path |
| "Create INDEX.md with required sections" | Write INDEX.md with the 5 sections: Active, Future, Clusters, Abandoned, Completed |
| "Add missing entries to INDEX.md" | Add orphaned intents to the appropriate INDEX.md section |
| "Remove stale references from INDEX.md" | Edit INDEX.md to remove ghost references |
| "Re-run installer" | Run `npx @zalom/plastic@latest --agent` |

For fixes the agent cannot handle automatically, explain what the user needs
to do manually.

### Step 6: Verify

After applying fixes, re-run the diagnostic script:

```bash
ruby ~/.plastic/scripts/doctor.rb --agent claude
```

Show the updated results.

- If all checks pass: announce success.
- If issues remain: explain what is still wrong and what the user can do.

## Post-Update Mode

When invoked from `plastic-update` (not directly by the user):

1. Run the diagnostic script as in Step 1.
2. If all checks pass: show a single line — **"Health check: all clear."**
3. If issues are found: show the full report (Steps 3-6).

This keeps the update flow clean when nothing is wrong.

## Important Notes

- The script is **read-only**. It inspects but never modifies files.
  All fixes are performed by the agent using standard tools.
- The script outputs JSON to stdout. Any diagnostic errors go to stderr.
- Non-zero exit codes mean "issues found", not "script crashed".
  Always parse stdout regardless of exit code.

## References

- Read `references/gates-stuck-detection.md` for the full gate enforcement table, bridge file pattern, and stuck detection thresholds when diagnosing gate failures or stuck agents
