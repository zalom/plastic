---
name: plastic-intent-continuing
description: >-
  The front door for resuming work. Use when the user says "continue", "resume", "pick up
  where we left off", "where was I", "what should I work on", names a specific intent to
  resume (by id or description, or `--intent {id}`), or names a roadmap or delivery batch to
  resume (`--roadmap {slug}`, "where is the roadmap", "where did that batch land"). Presents
  state and resumes at the last delivered stage; it never asks auto or guided, never boots
  (the SessionStart hook owns boot), and never drives work autonomously (plastic-auto does).
  Absorbs the former continuing, project-continuing, and roadmap-continuing skills and the
  read half of the former intent-starting skill (intent 304).
user-invocable: true
---

# Continuing: the front door for resuming work

One skill with three routes. It reads state and presents it; the work itself continues in
whatever mode the session is in (direct by default, `plastic-auto` when the owner says auto).
There is no lock to take and no mode to ask here: locks exist only for auto teams, and the
mode is the owner's word, not a question this skill puts.

**Boot is not this skill's job.** `hook-session-start` runs on every session start: the core
health check (`doctor --core`), `PLASTIC.md` and store or project state, the
`Plastic Core loaded - v{version}` banner. By the time this skill runs, core is loaded and
healthy or the banner already warned.

## Route

| Args or context | Route |
|---|---|
| `--intent {id}`, or the user names one specific intent to resume (by id or description) | Intent route (below) |
| `--roadmap {slug}`, or the user asks to continue or resume a roadmap or delivery batch | Roadmap route (below) |
| bare "continue", "resume", "what should I work on", or no target (the default) | Project route (below) |

State the chosen route in one line before doing anything ("Landing on the project board: no
specific intent or roadmap named.").

## Determine store

1. A project store under `~/.plastic/projects/{slug}/` whose registered path in
   `~/.plastic/projects.yml` matches the working directory means project mode; the
   SessionStart hook already detected this, the slug scopes the reads below.
2. Otherwise the global store, `~/.plastic/store/`.
3. Neither exists: announce "No Plastic store found. Run /plastic-install." and stop.

## Project route: land on the board

Land on the Markdown board through the `plastic-dashboard` skill; rendering belongs there.
Run the data payload and fill the matching template:
- project loaded: `ruby ~/.plastic/scripts/dashboard.rb project <slug> --data`
- otherwise (the global fallback): `ruby ~/.plastic/scripts/dashboard.rb continue --data`

Fill the template from `plastic-dashboard`'s `templates/` and present the filled Markdown in
your reply, every time: tool-call stdout and hook context are invisible to the user. Read
`references/board-fill.md` for the fill mechanics and the store-health line when filling the
board. The board load runs the scoped store check (`doctor --store <scope>`); its result
arrives in the payload as `store_health` and is shown as one line of data, never a blocker.

Priority order on the board: active intents first, then project context (governing plus
tactical intents in a registered project), then stale future intents for triage, then fresh
future intents as next work. A future intent older than `stale_threshold_days` (default 3) is
surfaced for triage without action: activate, abandon, or leave. Activating moves it to
`## Active` in `INDEX.md` and auto-commits. The board's ranked next-work order is computed by
`dashboard.rb`; cite the rule names only (Effort, Value, Flags, Override, Caps) and read
`plastic-dashboard`'s `references/classification.md` for their definitions.

When the tier root (the directory holding `INDEX.md`) has a mid-flight roadmap
(`ruby ~/.plastic/scripts/roadmap-next --roadmaps-dir <root>/roadmaps` reports a `state`
other than `none`), say so in one line and offer the roadmap route; the board still presents
project state and stops.

Then stop: "here is the state, what next?". Do not start executing work. When the user names
an intent, take the intent route.

## Intent route: resume one intent from its ledger

QMD-first when the intent is named by description: run
`ruby ~/.plastic/scripts/qmd-sync search "<terms>"` to find the candidate, then open the
authoritative intent file. The command is a no-op when QMD is absent; fall back to
`INDEX.md`.

If the intent is terminal (`## Completed` or `## Abandoned` in `INDEX.md`): print the
intent screen (Status shows the terminal section, Next is empty), summarize its
`outcome.md`, and ask what is next; never reopen it.

For a live intent's directory:

1. **Read `savepoint.md` first.** It is a deterministic, append-only ledger, one line per
   event, newest at the bottom: `{utc-iso8601}  {Stage}  {milestone}`. Classify the stage
   from the last line alone (the table in `references/boarding-matrix.md`, read when
   classifying), then verify only that line's artifact is real (sentinel-aware:
   `Savepoint.stage_file_present?`). Do not re-probe every lifecycle file.
2. **Stale ledger.** When the last line disagrees with the files on disk, rebuild the ledger from
   disk and note the correction. A rebuilt ledger is the file-landing skeleton, which still
   pins the stage:
   ```bash
   ruby -r ~/.plastic/scripts/lib/savepoint -e 'Savepoint.rebuild_savepoint("<intent_dir>")'
   ```
3. **Read the hand-off.** The newest `~/.plastic/store/.sessions/<day>/handoff--*.md` (today,
   else the newest prior day) is the prior session's own account of where things stand; read
   it after the ledger, never instead of it.
4. **Derive the next step:** the first unchecked item in `checklist.md` when it exists, else
   the next thing the stage needs (see the matrix). The newest `## Insights` entry supplies
   the human-readable context; an entry marked `(autonomous)` means an auto team was
   delivering it, so say so and offer to hand back to `plastic-auto`.
5. **Print the intent screen, then continue at that stage.** Run
   `ruby ~/.plastic/scripts/intent-screen <intent_dir>` and print its output as it is: the
   title, the field table, and the Steps table come from the record, never by eye. Under it
   write **What this means** as two to four bullets in plain words (what the intent is for,
   what has landed, what is left, any defect named by step), then close with
   **needs input:** naming the first open step. The screen's shape is
   `templates/intent-screen.md`; the script fills it, the session never edits the numbers.
   Then continue the work in the session's current mode. In auto mode the running team
   already holds the delivery lock; if a lock is held by a session that is gone, the
   `plastic-doctor` skill's lock section repairs or reclaims it.

## Roadmap route: resume the mid-flight roadmap

1. Resolve the tier root (project or global) and run the shared reader in which mode:
   ```bash
   ruby ~/.plastic/scripts/roadmap-next --roadmaps-dir <root>/roadmaps --which
   ```
   Read `state` and the winning `roadmap`. A `tie` lists `tie_candidates` to present side by
   side and let the user pick; never pick silently. The reader ranks liveness the way
   `references/liveness-ranking.md` describes (read it when a ranking needs explaining): a
   `delivering` or `blocked` entry wins, else the newest ledger or `## Log` timestamp.
   `roadmaps/<slug>.savepoint.md` is a derived signal read here, never a status field;
   `INDEX.md` stays the sole status writer.
2. **Present state:** the roadmap's `## Goal`, the current batch with each entry's mirrored
   status, the ledger's newest line beside the newest `## Log` line. Read
   `../plastic-conventions/references/roadmaps.md` for the file format and the status-mirror
   rule when a roadmap file needs interpreting.
3. Then continue with the next dispatchable entry in the session's mode: direct work on it,
   or `plastic-auto` when the owner says auto. The coordinator that drives a batch appends
   to `roadmaps/<slug>.savepoint.md` at its dispatch, merge, park, and handoff points with
   `ruby ~/.plastic/scripts/roadmap-savepoint append`; this skill only reads it.

## References

| Trigger | Read |
|---|---|
| Filling the board on the project route | `references/board-fill.md` |
| Classifying the stage from the ledger's last line | `references/boarding-matrix.md` |
| Explaining why one roadmap ranked above another | `references/liveness-ranking.md` |
| Saving or restoring context across a long session, or debugging a resume | `references/context-management.md` |
