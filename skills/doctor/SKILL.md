---
name: plastic-doctor
description: Use when diagnosing Plastic installation health, after updates, or when something seems broken. Runs checks and reports findings with fix options.
user-invocable: true
---

# Doctor: Plastic Health Check

## Scopes

Doctor has three scopes. Pick the right one for the situation:

| Scope | Flag | When it runs | States |
|-------|------|--------------|--------|
| Core check | `--core` | SessionStart hook (automatic), also available on demand | Binary: pass or error |
| Store check | `--store [global\|<slug>]` | Dashboard load, `plastic-project-continuing` | Three-state: pass / warn / fail |
| Full check | (no flag) | After every update (automatic), or `/plastic-doctor` | Three-state: pass / warn / fail |

### `--core` (binary, operational-readiness only)

Checks ONLY that Plastic is loaded and ready for work: agent registration (skills,
subagents, hooks/harnesses present and registered), core files (manifest-backed
presence/hash checks, excluding `agent_model_drift`, which is a non-boot
config-honoring check, never run at core), manifest sync (global + agent manifest
SHA256), every registered project's path resolving to a real, existing directory,
and the global store being reachable (`INDEX.md` present; no orphan/ghost content
scanning). Result is binary: exit 0 on pass, non-zero on error. It never produces
warnings, and it never scans store content.

It checks two install manifests as part of core files and manifest sync:

- `~/.plastic/manifest.json` (global manifest, covers PLASTIC.md and global scripts)
- `~/.claude/plastic/manifest.json` (agent-side manifest, covers agent scripts and hooks)

Each manifest maps a file path to its SHA256.

**On failure**, the report states this guided route, in order:

1. Run `plastic doctor --fix` (the Fix all / Select individually / Skip router from
   Step 4-5 below).
2. If that does not resolve it, roll back to the last known-good version via
   `plastic-rollback` (restores from the local, append-only `versions.json` ledger of
   versions actually run).
3. Optionally report the issue via the feedback command (`scripts/feedback-report`,
   backing the `plastic-feedback` skill), which composes a local report plus a
   prefilled GitHub issue URL and never holds a credential or contacts GitHub
   directly.

### `--store [global|<slug>]`

Checks the operations Plastic itself depends on in one store: QMD search reachability (scoped
to that store's own collection; global uses `plastic-global`, a project slug uses
`plastic-<slug>`), sources/chain resolution, cross-store resolution, INDEX parsing, and links
projection. A project slug also checks tool readiness (Serena, Enola): each is a pass whether
present or absent, present naming it available, absent noting it as an optional integration
never installed by doctor. Scope options:

- No argument (`:all`): checks all stores (global and all project stores), QMD reachability
  unscoped across every collection.
- `global`: checks only the global store, QMD scoped to `plastic-global`, no tool-readiness
  checks (code-navigation tools have no meaning against the global store).
- A project slug (e.g. `--store plastic`): checks only that project's store, QMD scoped to
  `plastic-<slug>`, plus Serena/Enola readiness for that project.

Produces three-state results (pass / warn / fail) and is run per-scope at dashboard load time:
the global board uses `--store global`, a project board uses `--store <slug>`. **This IS the
load-time full project check** named by 219's doctrine: no separate mechanism exists or is
needed, since a project slug's scan already carries every per-project finding scoped to that
project alone.

### Full doctor (no flag)

Runs the install-wide surface: agent registration, core files (including config-honoring
drift), manifest sync is core-only and not part of this run, deprecation checks, config-ask
checks, install-integrity checks, skill-lint (advisory), QMD reachability (unscoped, every
collection), and the global store's own conventions/done-signals content. **Never carries a
per-project finding**; that is `--store <slug>`'s job (see above). This is what
`/plastic-doctor` invokes, and it also runs automatically after every `plastic-update`
(informational, does not block or revert the update).

## When to Use

- User invokes `/plastic-doctor` (full check)
- After `plastic-update` completes (automatically, full check)
- When hooks aren't firing, skills aren't loading, or something seems broken
- When the user says "check plastic", "diagnose", "what's wrong with plastic"

Read `../plastic-conventions/references/gates-and-enforcement.md` for the transition-gate
mechanics, the audited escape, and gate logging before diagnosing a stuck or misbehaving gate.
This path resolves relative to this skill's own installed directory.

## Procedure

### Step 1: Run the diagnostic script

```bash
ruby ~/.plastic/scripts/doctor.rb --agent claude
```

Replace `claude` with the current agent type if known (`codex`, `hermes`).

Parse the JSON output from stdout. The script is read-only and never modifies
files. Errors go to stderr.

Exit codes indicate check results, not script failure:
- `0`: all checks passed
- `1`: warnings found
- `2`: failures found

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

This "Fix all / Select individually / Skip" prompt IS the router the spec calls
`doctor --fix-all` (intent 197): doctor itself never mutates anything (see Step 5's table and
"Important Notes" below); "Fix all" means "dispatch every fixable finding to the maintenance
tool or skill that owns that class of repair," one row per fix_hint pattern.

### Step 5: Apply fixes

Use the `fix_hint` value to determine the correct action:

| Fix hint pattern | Agent action |
|---|---|
| "chmod +x on the listed files" | Run `chmod +x` on each file listed in `details` |
| "Create missing directory" | Run `mkdir -p` on the path |
| "Create INDEX.md with required sections" | Write INDEX.md with the 5 sections: Active, Future, Clusters, Abandoned, Completed |
| "Add missing entries to INDEX.md" | Add orphaned intents to the appropriate INDEX.md section |
| "Remove stale references from INDEX.md" | Edit INDEX.md to remove ghost references |
| "Inject the missing required frontmatter field(s)" | Edit the intent's `{ID}--{slug}.md` frontmatter to add the missing key (e.g. `chain: []`) without touching other keys |
| "Run: provision-project-store {slug}" | Run `provision-project-store <slug>` (or invoke the `plastic-store-provisioning` skill) to create the missing store |
| "Re-run installer" | Run `npx -y @zalom/plastic@<channel> install --agent <agent>` (channel: -alpha->@alpha, -beta->@beta, else @latest) |
| "Run the Plastic installer to bootstrap the store" | Run `npx -y @zalom/plastic@<channel> install --agent <agent>` (channel: -alpha->@alpha, -beta->@beta, else @latest) to restore the global store's plastic_home directory or INDEX.md |
| "Dispatch plastic-store-curating ... revisions.md ..." | Invoke the `plastic-store-curating` (or the agent) to relocate the flagged section or ref into the intent's `revisions.md` via move-and-record (one dated, `[rule: <tag>]`-tagged entry per item), per plastic-conventions > references/maintenance-and-revisions.md. For a missing required section, restore or reproject it instead. |
| "Run scripts/project-links ... PRESERVES ... --drop-unbacked-links" | Run `ruby ~/.plastic/scripts/maintenance-run --tool project-links --intent <id> --apply` for the one flagged id (never run bare `project-links` against a real store outside the rare owner-approved batch exception, D2) |

For fixes the agent cannot handle automatically, explain what the user needs
to do manually. The `revisions.md` remedy is curator-applied (a move-and-record
relocation, not a mechanical edit) and stays human-gated by the Step 4
Fix / Select / Skip prompt.

Read `../plastic-conventions/references/maintenance-and-revisions.md` for WORK versus
MAINTENANCE, the `revisions.md` move-and-record contract, and the violation-tag catalog behind
the `revisions.md` remedy above.

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
2. If all checks pass, show a single line: **"Health check: all clear."**
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
