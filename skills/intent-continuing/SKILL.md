---
name: plastic-intent-continuing
description: >-
  Use when a specific intent is named to resume, by id or by description, or on `continuing
  --intent {id}`. Reads that intent's savepoint ledger and hands off to plastic-intent-starting.
  The general "continue" / new-session triggers belong to the plastic-continuing router, not
  here, so a bare "continue" does not settle on this skill directly. Boot (health check, core
  context, version, statusline) is owned by the SessionStart hook, not this skill. Does not
  drive work autonomously (that is plastic-auto).
user-invocable: true
---

# Continuing (intent route)

`plastic-intent-continuing` is the intent route of `plastic-continuing`. It resumes ONE
specific intent by its savepoint ledger, then hands off to `plastic-intent-starting`. It does
NOT land on a dashboard and does NOT execute work autonomously (that is `plastic-auto`); both
of those are other routes' jobs.

**Boot is not this skill's job.** The `hook-session-start` hook already runs by construction on
every session start: it runs the core health check (`doctor --core`), primes `PLASTIC.md` +
store/project state, and prints the `Plastic Core loaded - v{version}` banner. The
`plastic-statusline` hook sets the statusline. So by the time this skill runs, core is loaded
and healthy (or the banner already warned otherwise). This skill picks up from there and
resumes the named intent. This is the seam future continue-flags build on (see [[39]]).

## When to Use
- A specific intent is named to resume, by id or by description
- `continuing --intent {id}`

## Determine Store

1. **Global store** - `~/.plastic/INDEX.md` exists → global mode.
2. **Local store** - a project store under `~/.plastic/projects/{slug}/` whose registered
   path (in `~/.plastic/projects.yml`) matches the current working directory → project mode.
   The SessionStart hook already detects this; here you only need the slug to scope the
   named intent's store.
3. If neither exists → announce "No Plastic store found. Run /plastic-install."

## Conditional Ledger-Resume

Fires ONLY when the user explicitly asks to continue a SPECIFIC intent, or an agent is
instructed to continue one. It is not part of every boot.

QMD-first (when available): when the user names the intent by description rather than id, before
scanning the store with grep/Read run `ruby ~/.plastic/scripts/qmd-sync search "<terms>"` to
surface the candidate intent, then open the authoritative intent file for the hit you resume. The
command is a no-op when QMD is absent, so fall back to the existing INDEX.md / file scan.

For that intent's directory:

1. **Read `savepoint.md` FIRST (intent 81).** It is a deterministic, append-only ledger
   (one line per event, newest at the bottom): `{utc-iso8601}  {Stage}  {milestone}`. Classify
   the state from the **last line** alone, then verify ONLY that line's artifact. The bookends
   are fixed: first line `What  created`, last line either a cycle position or
   `Done  delivered|abandoned`.

   | Last line | State | Verify only |
   |---|---|---|
   | `What  {id}--{slug}.md` | born / parked | intent file exists |
   | `Why  started` | Why entered, no spec yet | spec.md not yet real; continue Why |
   | `Why  spec.md created` | Why done | spec.md present; continue to How |
   | `How  started` / `How  plan.md created` | How in progress | plan.md; continue How |
   | `How  checklist.md created` / `Exec  started` | ready for / in Exec | plan.md + checklist.md present; continue Exec |
   | `Exec  outcome.md created` | Exec done | outcome.md present; ready to complete |
   | `Done  delivered` / `Done  abandoned` | terminal | do NOT cycle-resume; INDEX is authoritative |

2. **Verify the stage file.** Confirm only the last line's artifact exists and is non-empty
   (ledger `How  plan.md created` → `plan.md` must be present and non-empty). Do not re-probe
   every lifecycle file.
3. **Drift handling.** If the ledger's last line disagrees with files-on-disk, rebuild the
   ledger from filesystem state and note the correction. A rebuilt ledger is the file-landing
   skeleton (no `started`/`Done` lines), which still pins cycle position:
   ```bash
   ruby -r ~/.plastic/scripts/lib/bridge -e 'Bridge.rebuild_savepoint("<intent_dir>")'
   ```
4. **Derive the next step:**
   - First unchecked item in `checklist.md` if it exists, else
   - "advance to the next lifecycle stage" (e.g. ledger shows Why/spec.md → next is How).
   - The newest `## Insights` entry supplies human-readable context (Insights are
     append-only, newest at the bottom).
5. **Announce, then hand off to `plastic-intent-starting`:**
   ```
   Resuming intent [ID] - [name]
   Store: [global | project:<slug> | local]
   Stage: [from ledger last line]
   Next step: [first unchecked checklist item | advance to <stage>]
   Context: [newest ## Insights entry]
   Drift: [none | ledger rebuilt from filesystem]
   ```
   Hand off to `plastic-intent-starting`: it takes the lock, boards at this station, and is
   where the single "auto or guided?" ask for the intent route lives, asked there exactly
   once and never duplicated here. Its auto branch is the one that hands off to `plastic-auto`;
   this skill never hands to `plastic-auto` directly.

## References

- Read `references/context-management.md` for the save/continue protocol and for
  debugging the resume flow.
