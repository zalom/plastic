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
| Store check | `--store [global\|<slug>]` | Dashboard load, the project route of `plastic-intent-continuing` | Three-state: pass / warn / fail |
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

1. Offer fixes in the `/plastic-doctor` conversation (the Fix all / Select individually /
   Skip router from Steps 4-5 below); doctor itself only reports, and each chosen repair
   is dispatched to the maintenance tool or skill that owns it.
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
| "Run: provision-project-store {slug}" | Run `provision-project-store <slug>` (see Provisioning a project store below) to create the missing store |
| "Re-run installer" | Run `npx -y @zalom/plastic@<channel> install --claude` (or `--codex`/`--hermes`/`--all` for that agent; channel: -alpha->@alpha, -beta->@beta, else @latest) |
| "Run the Plastic installer to bootstrap the store" | Run `npx -y @zalom/plastic@<channel> install --claude` (or `--codex`/`--hermes`/`--all`; channel: -alpha->@alpha, -beta->@beta, else @latest) to restore the global store's plastic_home directory or INDEX.md |
| "Relocate ... revisions.md ..." | Relocate the flagged section or ref into the intent's `revisions.md` via move-and-record (one dated, `[rule: <tag>]`-tagged entry per item), per plastic-conventions > references/maintenance-and-revisions.md. For a missing required section, restore or reproject it instead. |
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

## Doctor-Exclusions: Known-Exempt Findings

Some `savepoint_operational` findings can never legitimately close (a terminal intent with no
real `outcome.md` has no disposition to echo, and doctor never invents one), so each store
carries a `doctor-exclusions` file, sibling to that store's `INDEX.md`, recording
knowingly-exempt `(intent_id, rule)` pairs. Format: one `rule_name id id id` line per rule,
blank lines and `#` comments ignored. v1 honors exactly one rule, `savepoint_operational`.

**Reading the count.** When any exclusion applies, the `savepoint_operational` check's message
folds in the count and the file's path, e.g. `"... (3 excluded via ~/.plastic/doctor-exclusions)"`.
A malformed line in the file forces the check to `warn` with the parse error in `details`, even
when zero real gaps remain, so a broken file is never silently permissive.

**Both surfaces, one line.** A registration is honored by the store-wide `savepoint_operational`
check and by the per-intent `doctor.rb --intent <id>` run, which reports the same missing
`savepoint.md` under the check name `intent_savepoint_truthful`. Register the id once. The
per-intent run honors it only for an intent that is terminal in `INDEX.md`, and never suppresses
a phantom-savepoint-line finding.

**Hand-editing.** The file is plain text; add a line (or append ids to an existing rule line) and
save. No installer step, no reindex, and no `revisions.md` entry is required or written.

**Populating it in bulk.** Run the maintenance tool, dry-run first:

```bash
ruby ~/.plastic/scripts/maintenance-run --tool register-exclusions
```

This computes every current `savepoint_operational` violation across all stores (or one store
via `--store <key>`), through doctor's own finding function, and prints what it would register
without writing anything. Review the output, then re-run with `--apply` to write the file(s) and
land one scoped git commit. It unions with any existing hand-added ids (never drops one) and
skips, rather than aborts on, any intent dir holding a fresh delivery lock.

**Dead-row notice.** A registered row can go dead (gap repaired, id mistyped, or the intent
directory gone). When any row is dead, the message adds a second suffix next to the exclusion
count naming the count, the file, and the prune command - purely informational, status and exit
code unchanged. Prune it the same way, dry-run first: register-exclusions --prune [--apply]. It
removes exactly the dead rows through the same writer and commit, but holds back an id whose
intent dir carries a fresh lock or has not gone terminal yet (nothing to suppress there yet),
naming both as kept.

## Locks (auto teams only)

Locks exist for auto teams: a `delivery.lock` file in the intent directory names the owning
session, and the `record` hook refreshes its mtime on every edit (the lease heartbeat; stale
means older than the TTL). Direct work takes no lock. When a lock reads held by a session
that is gone, when work resumes after a crash, reboot, or `/tmp` wipe, or when the user says
"fix the lock", "who holds the lock", or "reclaim the lock", use the CLI (intent 304 folded
the former locking skill here):

| Verb | What it does | When |
|---|---|---|
| `who` | Owner, heartbeat, claims, delegates, from durable files only | Safe inspection; needs `--intent-dir` |
| `status` | Lock file, pointer cache, freshness, agreement | Always safe; run first |
| `fix` | Idempotent repair from disk truth for this session; never touches a fresh foreign lock | Interrupted work, corrupt state, `/tmp` wiped |
| `release` | The owner clears the lock | Ending or abandoning an auto delivery |
| `reclaim` | Explicit takeover of a stale lock; appends an audit line to `savepoint.md` | The owner is gone and the lease expired |
| `delegate` | The owner registers a subagent session, or marks it `finished` or `failed` | Auto-team orchestration |

```
ruby ~/.plastic/scripts/plastic-lock status --intent-dir <store>/<id>--<slug>
ruby ~/.plastic/scripts/plastic-lock who --intent-dir <store>/<id>--<slug>
ruby ~/.plastic/scripts/plastic-lock fix --intent-dir <store>/<id>--<slug>
ruby ~/.plastic/scripts/plastic-lock reclaim --intent-dir <store>/<id>--<slug>
```

`fix` exits non-zero when another session holds a fresh lock: back off, `status` shows the
owner. `reclaim` refuses a fresh lock; every takeover is audited. The lock file's mtime is the
sole freshness truth. Never delete a lock file by hand. Read
`../plastic-conventions/references/locks-and-worktrees.md` when a lock question goes beyond
these verbs (claims, worktrees, the station ledger).

## Provisioning a project store

When a project is registered in `~/.plastic/projects.yml` but has no store on disk (doctor
reports `project_store_dir`), provision it (intent 304 folded the former provisioning skill
here). The slug is the project's key under `projects`; an unregistered slug exits non-zero and
creates nothing, and this procedure never edits `projects.yml`.

```bash
ruby ~/.plastic/scripts/provision-project-store <slug>
ruby ~/.plastic/scripts/qmd-sync register --store ~/.plastic/projects/<slug>/store
```

The provisioner is pure filesystem and idempotent: it creates
`~/.plastic/projects/<slug>/store/` with `.gitkeep`, writes `INDEX.md` and `project.yml` only
when missing, and never clobbers. The QMD registration is a separate, optional step that
no-ops when QMD is absent. New projects are provisioned by `plastic-project-creating`, not here.
