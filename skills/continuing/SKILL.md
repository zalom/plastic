---
name: plastic-continuing
description: Use when the user says "continue", "resume", or "pick up where we left off", or when starting a new session. Boots Plastic — runtime health check, loads core context + store/project state, prints version + statusline, and lands on the right dashboard — then presents choices. Does not drive work autonomously (that is plastic-auto).
---

# Continuing

`plastic-continuing` is a deterministic **boot orchestrator**. It loads and presents choices,
then stops. It does NOT execute work autonomously (that is `plastic-auto`) and does NOT render
the dashboard itself (it only invokes it).

## When to Use
- UserPromptSubmit hook detects "continue" (automatic)
- User says "continue", "resume", or "pick up where we left off"
- Starting a new session with an existing Plastic store

## Determine Store

1. **Global store** — `~/.plastic/INDEX.md` exists → global mode.
2. **Local store** — a project store under `~/.plastic/projects/{slug}/` whose registered
   path (in `~/.plastic/projects.yml`) matches the current working directory → project mode.
   Project detection happens in boot step 2 below; this just records that a local store is
   in play.
3. If neither exists → announce "No Plastic store found. Run /plastic-install."

## Boot Sequence (run in this fixed order)

### 1. Core doctor (health first)
Run the fast runtime-liveness check synchronously (it returns in well under a second):

```bash
ruby ~/.plastic/scripts/doctor.rb --core
```

Print one compact health line:
- All pass → `Plastic core: healthy`
- Otherwise → `Plastic core: issues` followed by the failing checks (name + message).

This runs first so a broken runtime (missing hooks, scripts, core files) surfaces before any
state is loaded on top of it. For a full diagnosis, point the user at `/plastic-doctor`.

### 2. Load core (context + state)
- Prime `PLASTIC.md` and the harness docs so the conventions are in mind.
- Load live state:
  - Read the active store `INDEX.md` (`## Active`, `## Future`).
  - Read `~/.plastic/projects.yml`.
  - **Detect the current project** by matching CWD against registered project paths.
  - If in a project: load that project's `INDEX.md`; load the governing intent (from
    `parent` in projects.yml) and the tactical intents from
    `~/.plastic/projects/{slug}/store/`.

### 3. Version + statusline
- Print the current Plastic version (from `~/.plastic/VERSION`).
- Set the statusline.

### 4. Dashboard
Invoke the dashboard. Rendering belongs to the dashboard skill, not here — only invoke:
- Project loaded → `ruby ~/.plastic/scripts/dashboard.rb project <slug>`
- Otherwise → `ruby ~/.plastic/scripts/dashboard.rb continue`

Show its output verbatim. See `plastic-dashboard` for how to read the matrix.

### Then stop
Present "here is the state, what next?" and wait. Offer active intents first, then future
intents. Do not start executing work. The branches below are the only follow-ups:
- User/agent names a specific intent to continue → **Conditional ledger-resume** (below).
- User says "auto" / an agent is instructed to deliver → hand to `plastic-auto`.

## Conditional Ledger-Resume

Fires ONLY when the user explicitly asks to continue a SPECIFIC intent, or an agent is
instructed to continue one. It is not part of every boot. For that intent's directory:

1. **Read `savepoint.md`.** It is a deterministic, append-only stage ledger (one line per
   milestone, newest at the bottom): `{utc-iso8601}  {Stage}  {milestone}`. The **last line =
   current stage**.
2. **Verify the stage file.** Confirm the file the ledger names exists and is non-empty
   (ledger `How  plan.md created` → `plan.md` must be present and non-empty).
3. **Drift handling.** If the ledger's last line disagrees with files-on-disk, rebuild the
   ledger from filesystem state and note the correction:
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

## References

- Read `references/context-management.md` for the full save/continue protocol and for
  debugging the resume flow.
