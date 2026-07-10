---
name: plastic-intent-continuing
description: 'Use when the user says "continue", "resume", or "pick up where we left off", or when starting a new session. Continues work with the latest project context: lands on the right dashboard, then presents choices. Boot (health check, core context, version, statusline) is owned by the SessionStart hook, not this skill. Does not drive work autonomously (that is plastic-auto).'
user-invocable: true
---

# Continuing

`plastic-intent-continuing` continues work. It presents the latest state via the dashboard and offers
choices, then stops. It does NOT execute work autonomously (that is `plastic-auto`) and does
NOT render the dashboard itself (it only invokes it).

**Boot is not this skill's job.** The `hook-session-start` hook already runs by construction on
every session start: it runs the core health check (`doctor --core`), primes `PLASTIC.md` +
store/project state, and prints the `Plastic Core loaded — v{version}` banner. The
`plastic-statusline` hook sets the statusline. So by the time this skill runs, core is loaded
and healthy (or the banner already warned otherwise). This skill picks up from there and
continues work. This is the seam future continue-flags build on (see [[39]]).

## When to Use
- UserPromptSubmit hook detects "continue" (automatic)
- User says "continue", "resume", or "pick up where we left off"
- Starting a new session and you want to resume work with the latest context

## Determine Store

1. **Global store** — `~/.plastic/INDEX.md` exists → global mode.
2. **Local store** — a project store under `~/.plastic/projects/{slug}/` whose registered
   path (in `~/.plastic/projects.yml`) matches the current working directory → project mode.
   The SessionStart hook already detects this; here you only need the slug to scope the
   dashboard.
3. If neither exists → announce "No Plastic store found. Run /plastic-install."

## Continue (present the dashboard)

Land on the Markdown board via the `plastic-dashboard` skill. Rendering belongs there, not
here — run the data payload and fill + present the matching template:
- Project loaded → `ruby ~/.plastic/scripts/dashboard.rb project <slug> --data`
- Otherwise → `ruby ~/.plastic/scripts/dashboard.rb continue --data`

Fill the matching template from this skill's `templates/` and **present the filled Markdown
in your reply** (every time, non-optional). If the reply does not contain the filled Markdown,
the user sees nothing — tool-call stdout and hook `additionalContext` are both invisible to
them. `hook-continue` also emits a one-line `systemMessage` summary as a hook-owned fallback;
treat it as a floor only, never as a substitute for presenting the full board here. See
`plastic-dashboard` for the fill rules and entry flow.

The board load runs the scoped store check on every load (`doctor --store <scope>`): the
global board runs `--store global` and a project board runs `--store <slug>`. The result
arrives in the payload as `store_health`; surface it as a one-line store-health note. It is
non-fatal (a warn or fail is shown as data, it does not block continuing).

### Then stop
Present "here is the state, what next?" and wait. Offer active intents first, then future
intents. Do not start executing work. The branches below are the only follow-ups:
- User/agent names a specific intent to continue → **Conditional ledger-resume** (below).
- User says "auto" / an agent is instructed to deliver → hand to `plastic-auto`.

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
5. **Announce and stop:**
   ```
   Resuming intent [ID] — [name]
   Store: [global | project:<slug> | local]
   Stage: [from ledger last line]
   Next step: [first unchecked checklist item | advance to <stage>]
   Context: [newest ## Insights entry]
   Drift: [none | ledger rebuilt from filesystem]
   ```
   Then proceed with the next step. Autonomy is `plastic-auto`'s job — if the intent's
   `## Insights` contains `(autonomous)` entries, it was being delivered autonomously; hand
   to `plastic-auto` to continue from the current stage.

## Priority Order

1. **Active intents first** — surface work in progress.
2. **Project context** — if in a registered project, show governing + tactical intents.
3. **Stale future intents** — surface for triage (see below).
4. **Fresh future intents** — offer as next work.

## Stale Future Intents

If a future intent's `created` date is older than the configured `stale_threshold_days`
(default 3), surface it for triage without taking action:

```
Stale future intents (no action taken):

- [ID — name] (X days old)
  a) Activate — start working on it now
  b) Abandon — mark as abandoned
  c) Defer to agent: implement | research | ideate
  d) Auto — go fully autonomous (invokes plastic-auto)
```

When the user activates a future intent, move it to `## Active` in INDEX.md and auto-commit.

**Defer to agent: research.** Selecting `research` is a real dispatch, not a label. Resolve
`plastic-future-intent-researcher`'s model via `read-config agents.models.<basename> --project
<repo>` (project override, then global, then the shipped tier default) rather than relying on
bare frontmatter, which also honors a sanctioned `agents.models.<name>` override if one is
configured. Dispatch the agent (Agent tool, `subagent_type: "plastic-future-intent-researcher"`)
on the selected stale future intent, passing the resolved model explicitly. The agent writes its
findings into that intent's `## Context` (see `agents/plastic-future-intent-researcher.md`); it
does not itself dispatch further sub-agents. Once it returns, re-present the stale-future-intent
triage so the user can act on the fresh findings now on record.

## References

- Read `references/context-management.md` for the full save/continue protocol and for
  debugging the resume flow.
